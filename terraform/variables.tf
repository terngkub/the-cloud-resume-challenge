variable root_domain_name {
    description = "Root domain name of the hosted site"
    type = string
}

variable full_domain_name {
    description = "Full domain name of the hosted site, pointing to the resume page"
    type = string
}

variable website_index_file {
    description = "Index file of the S3 static website"
    type = string
    default = "index.html"
}