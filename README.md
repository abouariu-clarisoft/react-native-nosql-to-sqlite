# react-native-nosql-to-sqlite

This library is used to map the collections of a Mongo database to a SQLite database using a configuration
file.

The configuration file contains the fields from every collection that should become columns in the SQLite database and all other fields will be saved as a stringified JSON in columns called `extra` in every table.

## Getting started

`$ npm install abouariu-clarisoft/react-native-nosql-to-sqlite --save`

#### iOS

1. Add the library dependency to your podfile:

	`pod 'react-native-nosql-to-sqlite', path: '../node_modules/react-native-nosql-to-sqlite'`
2. Open the `.xcworkspace` file and run the project.

#### Android

TBD

## Configuration file

#### Rules

- The root keys of the JSON configuration file must be the names of the NoSQL collections.

- Every key of a collection must specify the fields that will be saved as columns in the SQLite database.

- The fields can have the following attributes:

	- type (required) - an SQLite data type
	- pk (optional) - a boolean value that specifies whether the field is a primary key
	- references (optional) - the name of another collection. If this key is present, it is treated as a foreign key of the specified table.
	- referencesOn (optional) - if a foreign key is present, this field specifies the primary key in the referenced table.
	- manyOn (optional) - if this key is present, then the relationship between the two collections is considered many-to-many and an intermediary table will be automatically created.
- For embedded collections, a field can be specified by using the `_` separator.

#### Example
Considering the following `person.json` and `city.json` collection:

```
/// persons.json
[
	{
    	"_id": "SomePersonID",
        "firstName": "First Of",
        "lastName": "The Last",
        "someField": "something",
        "someOtherField": "something else or maybe the same",
        "addresses": [
        	{
            	"_id": "SomeAddressID",
                "cityId": "SomeCityID",
                "addressLine1": "Address of multiple people",
                "someField": "something",
                "someOtherField": "something else or maybe the same"
            },
        	{
            	"_id": "SomeOtherAddressID",
                "cityId": "SomeOtherCityID",
                "addressLine1": "Another address of multiple people",
                "someField": "something",
                "someOtherField": "something else or maybe the same"
            }            
        ]
    }
]

/// city.json
[
	{
    	"id": "SomeCityID",
        "name": "Some City Name"
    },
    {
    	"id": "SomeOtherCityID",
        "name": "Some Other City Name Or Maybe The Same"
    }
]
```

Assuming we want to map this collection and keep the `cityId` field in the persons table, we can use the following configuration:
```
{
	"person": {
    	"_id": {
        	"type": "VARCHAR(100)",
            "pk": true
        }
    	"firstName": {
        	"type": "VARCHAR(100)"
        },
        "lastName": {
        	"type": "VARCHAR(100)"
        },
        "addresses_cityId": {
        	"type": "VARCHAR(100)",
            "references": "city",
            "referencesOn": "cityId",
            "manyOn": true
        }
    }
}
```
A `city_person` table will be created that will contain the fields `cityId` and `personId`.

The `addresses` collection doesn't have to be specified in the configuration file because it's an embedded collection.

## Usage
```javascript
import RNDB from 'react-native-nosql-to-sqlite';

// Create and open database file, set the database configuration
RNDB.configureDatabaseWithConfig(config);

// Create tables and import data from JSON collections into SQLite
RNDB.importData();
