variable "service" {
  type = object({
    name      = string
    image     = string
    namespace = string
  })
}

variable "config" {
  type = object({
    base = string
    env  = string
    ecs  = string
  })
}

variable "metadata" {
  type = object({
    labels      = map(string)
    annotations = map(string)
  })
}

variable "ecs_image" {
  type = string
}
