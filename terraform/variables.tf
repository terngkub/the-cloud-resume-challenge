# Domain

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

# Lambda

variable lambda_runtime {
    description = "Lambda runtime for the visitor counter"
    type = string
    default = "python3.13"
}

variable lambda_handler {
    description = "Lambda handler of the visitor counter"
    type = string
    default = "main.lambda_handler"
}

variable lambda_file_name {
    description = "Zip file name of the visitor counter"
    type = string
    default = "visitor_counter.zip"
}