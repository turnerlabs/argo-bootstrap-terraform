variable "conftag" {
  default = "PROD"
}
variable "customer" {}
variable "package_size" {}
variable "products" {}
variable "disk_type" {
  default = "none"
}
variable "real_customer" {
  default = "none"
}
variable "artifacts_credentials" {}
variable "artifacts_endpoint" {}

resource "template_file" "bootstrap" {
  template = "${file("${path.module}/bootstrap.tpl")}"
  vars {
    conftag = "${var.conftag}"
    customer = "${var.customer}"
    package_size = "${var.package_size}"
    products = "${var.products}"
    disk_type = "${var.disk_type}"
    real_customer = "${var.real_customer}"
    artifacts_credentials = "${var.artifacts_credentials}"
    artifacts_endpoint = "${var.artifacts_endpoint}"
  }
}

output "user_data" {
  value = "${template_file.bootstrap.rendered}"
}
