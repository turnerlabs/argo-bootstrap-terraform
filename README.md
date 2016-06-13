Argo bootstrap script to be used as user_data input for terraform modules

Example usage:

module "bootstrap" {
  source = "git::ssh://git@bitbucket.org/vgtf/argo-bootstrap-terraform.git?ref=v0.0.1"
  customer = "cnn"
  package_size = "2x4x32"
  products = "test-test:dev,testing:prod"
}

resource "aws_instance" "node1" {
    user_data = "${module.bootstrap.user_data}"
}
