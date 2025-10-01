#######
### setup
# python -m venv ./venv
# source ./venv/bin/activate
# pip install boto3 botocore
### dry-run
# python ecr_delete_push_images.py --prefix github/ --account-id 123456789012 --region us-east-1 --dry-run --profile myprofile
#
### dry-run with logging
# python ecr_delete_push_images.py --prefix github/ --account-id 123456789012 --region us-east-1 --dry-run --profile myprofile --verbose --log-file script.log
#
### run for real
# python ecr_delete_push_images.py --prefix github/ --account-id 123456789012 --region us-east-1 --profile myprofile
#######

#!/usr/bin/env python3
import argparse
import logging
import subprocess
from typing import List, Tuple

import boto3
from botocore.session import Session
from botocore.exceptions import BotoCoreError, ClientError


def setup_logging(verbose: bool, log_file: str | None) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    fmt = "%(asctime)s %(levelname)s %(message)s"
    datefmt = "%Y-%m-%dT%H:%M:%S%z"

    handlers = [logging.StreamHandler()]
    if log_file:
        handlers.append(logging.FileHandler(log_file))

    logging.basicConfig(level=level, format=fmt, datefmt=datefmt, handlers=handlers)


def get_ecr_client(region: str, profile: str | None):
    if profile:
        boto_sess = Session(profile=profile)
        return boto_sess.create_client("ecr", region_name=region)
    return boto3.client("ecr", region_name=region)


def get_repositories_with_prefix(ecr, prefix: str) -> List[str]:
    repos: List[str] = []
    paginator = ecr.get_paginator("describe_repositories")
    for page in paginator.paginate():
        for repo in page.get("repositories", []):
            name = repo.get("repositoryName", "")
            if name.startswith(prefix):
                repos.append(name)
    logging.info("Discovered %d repositories with prefix '%s'", len(repos), prefix)
    logging.debug("Repositories: %s", repos)
    return repos


def get_last_three_tags(ecr, repo_name: str) -> List[str]:
    """
    Return up to 3 most recently pushed *tags* for the repository.
    If an image has multiple tags, they are considered in order but we cap list at 3.
    """
    try:
        paginator = ecr.get_paginator("describe_images")
        images = []
        for page in paginator.paginate(
            repositoryName=repo_name, filter={"tagStatus": "TAGGED"}
        ):
            images.extend(page.get("imageDetails", []))

        if not images:
            return []

        images.sort(key=lambda x: x.get("imagePushedAt", 0), reverse=True)

        tags: List[str] = []
        for img in images:
            for t in img.get("imageTags", []):
                if t not in tags:
                    tags.append(t)
                if len(tags) == 3:
                    break
            if len(tags) == 3:
                break
        return tags
    except (BotoCoreError, ClientError) as e:
        logging.error("Failed to list image tags for %s: %s", repo_name, e)
        return []


def docker_login(account_id: str, region: str, profile: str | None) -> None:
    login_cmd = ["aws", "ecr", "get-login-password", "--region", region]
    if profile:
        login_cmd.extend(["--profile", profile])

    logging.debug("Running: %s", " ".join(login_cmd))
    auth = subprocess.run(
        login_cmd, capture_output=True, text=True, check=True
    )

    registry = f"{account_id}.dkr.ecr.{region}.amazonaws.com"
    logging.info("Logging into Docker registry: %s", registry)
    subprocess.run(
        ["docker", "login", "--username", "AWS", "--password-stdin", registry],
        input=auth.stdout,
        text=True,
        check=True,
    )


def process_tag(
    ecr, repo_name: str, tag: str, account_id: str, region: str, dry_run: bool
) -> Tuple[bool, str]:
    """Process a single tag: pull -> delete -> push. Returns (success, message)."""
    image_uri = f"{account_id}.dkr.ecr.{region}.amazonaws.com/{repo_name}:{tag}"
    if dry_run:
        logging.info("[DRY-RUN] Would process: %s", image_uri)
        return True, "dry-run"

    try:
        logging.info("Pulling image: %s", image_uri)
        subprocess.run(["docker", "pull", image_uri], check=True)
        logging.info("Pulled image: %s", image_uri)
    except subprocess.CalledProcessError as e:
        logging.error("Failed to pull %s: %s", image_uri, e)
        return False, "pull-failed"

    try:
        logging.info("Deleting image tag from ECR: %s", image_uri)
        ecr.batch_delete_image(
            repositoryName=repo_name, imageIds=[{"imageTag": tag}]
        )
        logging.info("Deleted image tag in ECR: %s", image_uri)
    except (BotoCoreError, ClientError) as e:
        logging.error("Failed to delete %s in ECR: %s", image_uri, e)
        return False, "delete-failed"

    try:
        logging.info("Pushing image back to ECR: %s", image_uri)
        subprocess.run(["docker", "push", image_uri], check=True)
        logging.info("Pushed image back: %s", image_uri)
    except subprocess.CalledProcessError as e:
        logging.error("Failed to push %s: %s", image_uri, e)
        return False, "push-failed"

    return True, "ok"


def main():
    parser = argparse.ArgumentParser(
        description="Pull, delete, and push back last 3 tags of ECR repositories with a given prefix"
    )
    parser.add_argument("--prefix", required=True, help="Repository name prefix (e.g. github/)")
    parser.add_argument("--account-id", required=True, help="AWS account ID")
    parser.add_argument("--region", required=True, help="AWS region (e.g. us-east-1)")
    parser.add_argument("--profile", help="AWS CLI profile name (optional)")
    parser.add_argument("--dry-run", action="store_true", help="Preview actions without pulling/deleting/pushing")
    parser.add_argument("--log-file", help="Path to write logs (optional)")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose (DEBUG) logging")
    args = parser.parse_args()

    setup_logging(args.verbose, args.log_file)

    ecr = get_ecr_client(args.region, args.profile)

    if not args.dry_run:
        try:
            docker_login(args.account_id, args.region, args.profile)
        except subprocess.CalledProcessError as e:
            logging.critical("Docker login failed: %s", e)
            return

    repos = get_repositories_with_prefix(ecr, args.prefix)

    total_repos = 0
    total_tags = 0
    successes = 0
    failures = 0

    for repo in repos:
        tags = get_last_three_tags(ecr, repo)
        if not tags:
            logging.info("No recent tags found for repo: %s", repo)
            continue

        total_repos += 1
        logging.info("Processing repo: %s | Tags: %s", repo, tags)

        for tag in tags:
            total_tags += 1
            ok, reason = process_tag(ecr, repo, tag, args.account_id, args.region, args.dry_run)
            if ok:
                successes += 1
            else:
                failures += 1
                logging.warning("Action failed for %s:%s (%s)", repo, tag, reason)

    logging.info("=== SUMMARY ===")
    logging.info("Repositories touched: %d", total_repos)
    logging.info("Tags attempted: %d | Succeeded: %d | Failed: %d", total_tags, successes, failures)
    if args.dry_run:
        logging.info("Mode: DRY-RUN (no changes were made)")


if __name__ == "__main__":
    main()


