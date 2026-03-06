cat(jsonlite::toJSON(jsonlite::fromJSON('{\"s\":[{\"id\":\"m1\",\"v\":[1,2,3]}]}', simplifyDataFrame = FALSE, simplifyMatrix = FALSE), auto_unbox=TRUE))
