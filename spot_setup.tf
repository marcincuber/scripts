resource "aws_launch_template" "bastion" {
  count         = "${var.enable_circleci_bastion ? 1 : 0}"
  name_prefix   = "launch-template-ceng-k8s-cust-${var.environment}-cluster"
  image_id      = "${data.aws_ami.amazon_linux.id}"
  instance_type = "t2.small"
  key_name      = "ceng-dev"

  iam_instance_profile {
    name = "${aws_iam_instance_profile.bastion_role_profile.name}"
  }

  instance_market_options {
    market_type = "spot"
  }

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    security_groups             = ["${aws_security_group.bastion_ssh.id}"]
    subnet_id                   = "${aws_subnet.eu-west-1c-public-bastion.id}"
  }

  user_data = "${base64encode(data.template_file.userdata.rendered)}"
}

resource "aws_autoscaling_group" "bastion" {
  count               = "${var.enable_circleci_bastion ? 1 : 0}"
  name_prefix         = "customer-cluster-${var.environment}-bastion-scaling-group"
  desired_capacity    = 1
  max_size            = 1
  min_size            = 1
  vpc_zone_identifier = ["${aws_subnet.eu-west-1c-public-bastion.id}"]
  force_delete        = true

  launch_template {
    id      = "${aws_launch_template.bastion.id}"
    version = "$$Latest"
  }

  tags = [
    {
      key                 = "Name"
      value               = "ceng-k8s-cust-${var.environment}-bastion"
      propagate_at_launch = true
    },
    {
      key                 = "ServiceName"
      value               = "ceng-k8s-cust-${var.environment}-cluster"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "${var.environment}"
      propagate_at_launch = true
    },
  ]

  timeouts {
    delete = "15m"
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = ["aws_launch_template.bastion"]
}
