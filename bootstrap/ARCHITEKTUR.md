terraform {

&nbsp; backend "s3" {

&nbsp;   endpoint   = "http://10.10.30.10:9000"

&nbsp;   bucket     = "ralf-state"

&nbsp;   key        = "bootstrap/terraform.tfstate"

&nbsp;   region     = "us-east-1"

&nbsp;   access\_key = var.minio\_access\_key

&nbsp;   secret\_key = var.minio\_secret\_key



&nbsp;   skip\_credentials\_validation = true

&nbsp;   skip\_region\_validation      = true

&nbsp;   skip\_metadata\_api\_check     = true

&nbsp;   force\_path\_style            = true

&nbsp; }

}

