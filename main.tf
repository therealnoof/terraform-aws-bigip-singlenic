#
# Provider Declared
#
provider "aws" {
  region = "${var.region}"
  shared_credentials_file = "/home/ahernandez/Terraform/.aws/credentials-commercial-aws"
}

#
# Create a random id
#
resource "random_id" "id" {
  byte_length = 2
}

###########################
# Core Networking Created #
###########################

#
# Create the VPC 
#
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name                 = format("%s-vpc-%s", local.prefix, random_id.id.hex)
  cidr                 = local.cidr
  azs                  = ["${var.az}"]
  enable_nat_gateway   = "true"
  enable_dns_hostnames = "true"
}

#
# Create the IGW
#
resource "aws_internet_gateway" "single-nic-bigip" {
  vpc_id                = module.vpc.vpc_id
  tags = {
    Name = "single-nic-bigip"
  }
}


#
# Create the Route Table
#
resource "aws_route_table" "single-nic-bigip-table" {
  vpc_id                = module.vpc.vpc_id
  
    route {
    cidr_block          = "0.0.0.0/0"
    gateway_id          = "${aws_internet_gateway.single-nic-bigip.id}"  
  }
  tags = {
    Name = "single-nic-bigip-table"
  }
}

#
# Create the Route Table associations
#
resource "aws_route_table_association" "single-nic-bigip" {
  subnet_id             = "${aws_subnet.mgmt.id}" 
  route_table_id        = "${aws_route_table.single-nic-bigip-table.id}"
}

#
# Create the Main Route Table asscociation
#
resource "aws_main_route_table_association" "single-nic-bigip-table-association" {
  vpc_id                = module.vpc.vpc_id
  route_table_id        = "${aws_route_table.single-nic-bigip-table.id}"
}



#
# Create Ephemeral EIP for BIGIP
#
resource "aws_eip" "ephemeral_bigip" {
  vpc                         = true
  public_ipv4_pool            = "amazon"
}

#
# Create EIP Association with BIGIP MGMT Interface
#
resource "aws_eip_association" "bigip" {
  network_interface_id        = "${aws_network_interface.single-nic-bigip.id}"
  allocation_id               = "${aws_eip.ephemeral_bigip.id}"
}

#########################
# Create Security Group #
#########################

#
# Create General Security Group for all Instances/Subnets
#
resource "aws_security_group" "single-nic-bigip" {
  vpc_id                = module.vpc.vpc_id
  description           = "single-nic-bigip"
  name                  = "single-nic-bigip"
  tags = {
    Name = "single-nic-bigip-sg"
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

#
# Create Management Subnet 
#
resource "aws_subnet" "mgmt" {
  vpc_id                = module.vpc.vpc_id
  cidr_block            = "10.0.1.0/24"
  availability_zone     = "${var.az}"
  tags = {
    Name = "single-nic-bigip-mgmt"
    Group_Name = "single-nic-bigip-mgmt"
  }
}

#####################
# Create Interfaces #
#####################

#
# Create MGMT Network Interface for BIG-IP
#
resource "aws_network_interface" "single-nic-bigip" {
  private_ips           = ["10.0.1.150"]
  source_dest_check     = "false"
  subnet_id             = "${aws_subnet.mgmt.id}"
  security_groups       = ["${aws_security_group.single-nic-bigip.id}"]
  tags = {
    Name = "single-nic-bigip-mgmt"
  }
}

#
# Create BIG-IP - AWAF PAYG 1GIG
# 
resource "aws_instance" "bigip" {

  count                       = 1
  ami                         = "${var.awaf_ami}"  
  instance_type               = "m5.2xlarge"
  key_name                    = var.ec2_key_name  
  availability_zone           = "${var.az}"
  tags = {
    Name = "single-nic-bigip"
  }
  network_interface {
    network_interface_id      = "${aws_network_interface.single-nic-bigip.id}"
    device_index              = 0
  }
}

#############
# Variables #
#############

#
# Variables used by this example
#
locals {
  prefix            = "tf-single-nic-bigip"
  cidr              = "10.0.0.0/16"
  allowed_mgmt_cidr = "0.0.0.0/0"
  allowed_app_cidr  = "0.0.0.0/0"
}
