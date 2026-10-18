variable "table_name" {
  type    = string
  default = "ToggleMasterAnalytics"
}

variable "point_in_time_recovery" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
