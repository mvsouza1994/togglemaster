variable "prefix" {
  type    = string
  default = "togglemaster"
}

variable "repositories" {
  type = list(string)
  default = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service",
  ]
}

variable "keep_last_images" {
  type    = number
  default = 15
}

variable "tags" {
  type    = map(string)
  default = {}
}
