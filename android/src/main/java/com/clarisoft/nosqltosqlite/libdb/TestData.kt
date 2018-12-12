package com.clarisoft.nosqltosqlite.libdb

val DB_CONFIG = """
    {
    "cluster": {
        "_id": {
            "type": "VARCHAR(100)",
            "pk": true
        },
        "name": {
            "type": "VARCHAR(100)"
        },
        "updatedAt": {
            "type": "DATE"
        },
        "updatedBy": {
            "type": "VARCHAR(100)"
        },
        "deleted": {
            "type": "BOOLEAN"
        },
        "deletedAt": {
            "type": "DATE"
        }
    },
    "followUp": {
        "_id": {
            "type": "VARCHAR(100)",
            "pk": true
        },
        "date": {
            "type": "DATE"
        },
        "performed": {
            "type": "BOOLEAN"
        },
        "lostToFollowUp": {
            "type": "BOOLEAN"
        },
        "outbreakId": {
            "type": "VARCHAR(100)",
            "references": "outbreak",
            "referencesOn": "_id"
        },
        "personId": {
            "type": "VARCHAR(100)",
            "references": "person",
            "referencesOn": "_id"
        },
        "updatedAt": {
            "type": "DATE"
        },
        "updatedBy": {
            "type": "VARCHAR(100)"
        },
        "deleted": {
            "type": "BOOLEAN"
        },
        "deletedAt": {
            "type": "DATE"
        }
    },
    "language": {
        "_id": {
            "type": "VARCHAR(100)",
            "pk": true
        },
        "name": {
            "type": "VARCHAR(100)"
        },
        "deleted": {
            "type": "BOOLEAN"
        }
    },
    "languageToken": {
        "_id": {
            "type": "VARCHAR(100)",
            "pk": true
        },
        "token": {
            "type": "VARCHAR(100)",
            "unique": true
        },
        "languageId": {
            "type": "VARCHAR(100)",
            "references": "language",
            "referencesOn": "_id"
        },
        "translation": {
            "type": "VARCHAR(100)"
        },
        "deleted": {
            "type": "BOOLEAN"
        }
    },
    "location": {
        "_id": {
            "type": "VARCHAR(100)",
            "pk": true
        },
        "name": {
            "type": "VARCHAR(100)"
        },
        "parentLocationId": {
            "type": "VARCHAR(100)",
            "references": "language",
            "referencesOn": "_id"
        },
        "active": {
            "type": "BOOLEAN"
        },
        "deleted": {
            "type": "BOOLEAN"
        }
    },
    "outbreak": {
        "_id": {
            "type": "VARCHAR(100)",
            "pk": true
        },
        "deleted": {
            "type": "BOOLEAN"
        }
    },
    "person": {
        "_id": {
            "type": "VARCHAR(100)",
            "pk": true
        },
        "type": {
            "type": "VARCHAR(100)"
        },
        "outbreakId": {
            "type": "VARCHAR(100)",
            "references": "outbreak",
            "referencesOn": "_id"
        },
        "firstName": {
            "type": "VARCHAR(100)"
        },
        "middleName": {
            "type": "VARCHAR(100)"
        },
        "lastName": {
            "type": "VARCHAR(100)"
        },
        "age_years": {
            "type": "INT"
        },
        "age_months": {
            "type": "INT"
        },
        "gender": {
            "type": "VARCHAR(20)"
        },
        "occupation": {
            "type": "VARCHAR(100)"
        },
        "addresses_locationId": {
            "type": "VARCHAR(100)",
            "references": "location",
            "referencesOn": "_id",
            "manyOn": "_id"
        },
        "updatedAt": {
            "type": "DATE"
        },
        "updatedBy": {
            "type": "VARCHAR(100)",
            "references": "user",
            "referencesOn": "_id"
        },
        "deleted": {
            "type": "BOOLEAN"
        },
        "deletedAt": {
            "type": "DATE"
        }
    },
    "referenceData": {
        "_id": {
            "type": "VARCHAR(100)",
            "pk": true
        },
        "categoryId": {
            "type": "VARCHAR(100)",
            "references": "language",
            "referencesOn": "token"
        },
        "value": {
            "type": "VARCHAR(100)",
            "references": "language",
            "referencesOn": "token"
        },
        "deleted": {
            "type": "BOOLEAN"
        }
    },
    "relationship": {
        "_id": {
            "type": "VARCHAR(100)",
            "pk": true
        },
        "outbreakId": {
            "type": "VARCHAR(100)",
            "references": "outbreak",
            "referencesOn": "_id"
        },
        "active": {
            "type": "BOOLEAN"
        },
        "persons_0_id": {
            "type": "VARCHAR(100)",
            "references": "person",
            "referencesOn": "_id"
        },
        "persons_0_type": {
            "type": "VARCHAR(100)",
            "references": "language",
            "referencesOn": "token"
        },
        "persons_1_id": {
            "type": "VARCHAR(100)",
            "references": "person",
            "referencesOn": "_id"
        },
        "persons_1_type": {
            "type": "VARCHAR(100)",
            "references": "language",
            "referencesOn": "token"
        },
        "updatedAt": {
            "type": "DATE"
        },
        "updatedBy": {
            "type": "VARCHAR(100)",
            "references": "user",
            "referencesOn": "_id"
        },
        "deleted": {
            "type": "BOOLEAN"
        },
        "deletedAt": {
            "type": "DATE"
        }
    },
    "role": {
        "_id": {
            "type": "VARCHAR(100)",
            "pk": true
        },
        "name": {
            "type": "VARCHAR(100)"
        },
        "deleted": {
            "type": "BOOLEAN"
        }
    },
    "team": {
        "_id": {
            "type": "VARCHAR(100)",
            "pk": true
        },
        "name": {
            "type": "VARCHAR(100)"
        },
        "deleted": {
            "type": "BOOLEAN"
        }
    },
    "user": {
        "_id": {
            "type": "VARCHAR(100)",
            "pk": true
        },
        "email": {
            "type": "VARCHAR(100)"
        },
        "deleted": {
            "type": "BOOLEAN"
        },
        "deletedAt": {
            "type": "DATE"
        }
    }
}
"""