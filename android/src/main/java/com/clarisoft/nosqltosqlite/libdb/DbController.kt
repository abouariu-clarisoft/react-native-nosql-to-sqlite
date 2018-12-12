package com.clarisoft.nosqltosqlite.libdb

import android.content.ContentValues
import android.os.Environment
import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonElement
import com.google.gson.JsonObject
import com.google.gson.stream.JsonReader
import com.google.gson.stream.JsonWriter
import com.squareup.moshi.Moshi
import com.squareup.moshi.Types
import net.sqlcipher.database.SQLiteDatabase
import okio.Okio
import java.io.*


class DbController(configPath: String?, configJson: String?, private val database: Database) {
    private val mTables: MutableList<Table> = mutableListOf()
    private val gson: Gson = Gson()

    init {
        val moshi = Moshi.Builder().build()
        val mapAdapter = Types.newParameterizedType(Map::class.java, String::class.java, Any::class.java)
        val adapter = moshi.adapter<Map<String, Any>>(mapAdapter)


        val configMap = let {
            when {
                configPath != null -> adapter.fromJson(Okio.buffer(Okio.source(File(configPath))))
                        ?: throw IOException("Error parsing config")
                configJson != null -> adapter.fromJson(configJson)
                        ?: throw IOException("Error parsing config")
                else -> {
                    throw java.lang.IllegalStateException("Invalid config")
                }
            }
        }

        configMap.forEach { configObject ->
            mapConfigToTable(configObject)
        }
    }

    fun createConfigTables() {
        val rawSql = mapTablesToSqlString()
        log("executing $rawSql")
        database.execSQL(rawSql)
    }

    fun importFromJson(baseDir: String): String {
        var tableCount = 0
        var rowCount = 0

        val whoDir = File(Environment.getExternalStorageDirectory().path + "/" + baseDir)
        log("DIRECTORY: $whoDir")
        whoDir.walk().forEach { file ->
            if (file.isFile) {

                val reader = JsonReader(FileReader(file))
                val tableName = file.nameWithoutExtension

                val table = mTables.find(predicate = { t -> t.name == tableName })
                if (table != null) {
                    tableCount++
                    reader.beginArray()
                    database.mDb.transaction {
                        while (reader.hasNext()) {
                            val jsonElement = gson.fromJson<JsonObject>(reader, JsonObject::class.java)
                            val cv = ContentValues()
                            var entry: JsonElement?
                            var elementId: String? = null //stores element id for eventual use in many to many table
                            table.columns.forEach { columnEntry ->
                                entry = jsonElement?.get(columnEntry.key)
                                if (entry?.isJsonNull == false) {
                                    if (columnEntry.value.type == "BOOLEAN") {
                                        val valueBool = entry?.asBoolean
                                        cv.put(columnEntry.key, valueBool)
                                    } else {
                                        val valueString = entry?.asString
                                        if (columnEntry.key == "_id") {
                                            elementId = valueString
                                        }

                                        if (valueString != null) {
                                            cv.put(columnEntry.key, valueString)
                                        }
                                    }
                                } else {
                                    cv.putNull(columnEntry.key)
                                }
                                jsonElement.remove(columnEntry.key)
                            }
                            rowCount++

                            //import many on relations
                            if (!table.manyOnConstraints.isEmpty()) {
                                Log.d("", table.manyOnConstraints.toString())
                                table.manyOnConstraints.forEach { it ->
                                    val manyOnTableName = getManyOnTableName(table, it)

                                    val manyArray = jsonElement?.get(it.key.split("_")[0])?.asJsonArray
                                    manyArray?.forEach { manyObject ->
                                        val innerKey = manyObject?.asJsonObject?.get(it.key.split("_")[1])

                                        //check key is null
                                        if (innerKey?.isJsonNull != true) {
                                            innerKey?.asString?.let { inKeyString ->
                                                //                                                log(inKeyString)
//                                                log("put $inKeyString $elementId")
                                                val manyOnCv = ContentValues()
                                                manyOnCv.put("_id", "$elementId$inKeyString")
                                                manyOnCv.put("${table.name}Id", elementId)
                                                manyOnCv.put("${it.value.references}Id", inKeyString)
                                                insertValue(manyOnTableName, manyOnCv)
//                                                log("inserted in manyOnTable $manyOnTableName values $manyOnCv")
                                            }
                                        } else {
                                            val manyOnCv = ContentValues()
                                            manyOnCv.put("_id", "$elementId")
                                            manyOnCv.put("${table.name}Id", elementId)
                                            manyOnCv.putNull("${it.value.references}Id")
                                            insertValue(manyOnTableName, manyOnCv)
                                        }
                                    }
//                                    log(it.value.manyOn.toString() + "::" + it.value.references.toString() + "::" + it.value.referencesOn)
                                }
                            }
                            rowCount++
                            cv.put("extra", jsonElement.toString())
                            insertValue(tableName, cv)
                        }
                    }
                    reader.endArray()
                    reader.close()
                }
            }
        }
        return "Inserted $rowCount rows in $tableCount tables"
    }

    private fun insertValue(tableName: String, cv: ContentValues) {
        database.mDb.insertWithOnConflict(tableName, null, cv, SQLiteDatabase.CONFLICT_REPLACE)
    }

    fun mapTablesToSqlString(): String {
        if (mTables.isEmpty()) {
            throw IllegalStateException("Db Config has not been properly initialized")
        }
        val stringBuilder = StringBuilder()
        mTables.forEach { table ->
            stringBuilder.append("CREATE TABLE ${table.name} (\n${mapColumns(table.columns, table.constraints)}\n);\n")
            if (!table.manyOnConstraints.isEmpty()) {
                mapManyOn(table, stringBuilder)
            }
        }
        return stringBuilder.toString()
    }

    private fun mapConfigToTable(configObject: Map.Entry<String, Any>) {
        val tableName = configObject.key
        val columns = configObject.value as Map<*, *>
        val columnMap = HashMap<String, Column>().toSortedMap()
        val constraintMap = HashMap<String, Constraint>().toSortedMap()
        val manyOnMap = HashMap<String, ManyOnConstraint>().toSortedMap()
        columns.forEach { columnEntry ->
            val inMap = columnEntry.value as Map<*, *>

            val references = inMap["references"]
            var isMany = false
            if (references != null) {
                if (inMap["manyOn"] == null) {
                    log("references $references")
                    constraintMap[columnEntry.key as String] = Constraint(
                            references = references as String?,
                            referencesOn = inMap["referencesOn"] as String?
                    )
                } else {
                    isMany = true
                    manyOnMap[columnEntry.key as String] = ManyOnConstraint(
                            references = references as String?,
                            referencesOn = inMap["referencesOn"] as String?,
                            manyOn = inMap["manyOn"] as String?
                    )
                }
            }
            if (!isMany) {
                columnMap[columnEntry.key as String] = Column(
                        pk = inMap["pk"] as Boolean?,
                        type = inMap["type"] as String
                )
            }
        }
        val table = Table(tableName, columnMap, constraintMap, manyOnMap)
        mTables.add(table)
    }


    private fun getManyOnTableName(table: Table, references: Map.Entry<String, ManyOnConstraint>): String {
        return "${table.name}_${references.value.references}"
    }

    private fun mapManyOn(table: Table, stringBuilder: StringBuilder) {
        table.manyOnConstraints.forEach {
            val sql = """CREATE TABLE  ${getManyOnTableName(table, it)} (
_id VARCHAR(100) PRIMARY KEY,
${it.value.references}Id VARCHAR(100),
${table.name}Id VARCHAR(100),
extra VARCHAR(5000),

CONSTRAINT fk_${it.value.references} FOREIGN KEY (${it.value.references}Id) REFERENCES ${it.value.references}(${it.value.referencesOn})
ON DELETE SET NULL

CONSTRAINT fk_${table.name} FOREIGN KEY (${table.name}Id) REFERENCES ${table.name}(${it.value.referencesOn})
ON DELETE SET NULL);
"""
            stringBuilder.append(sql)
        }
    }

    private fun mapColumns(columns: Map<String, Column>, constraints: Map<String, Constraint>): String {
        val stringBuilder = StringBuilder()
        columns.keys.forEachIndexed { i, columnName ->
            val type = columns[columnName]?.type
            when {
                i < columns.keys.size - 1 -> stringBuilder.append("$columnName $type,\n")
                constraints.isEmpty() -> stringBuilder.append("$columnName $type,")
                else -> stringBuilder.append("$columnName $type, \n")
            }
        }

        if (constraints.isEmpty()) {
            stringBuilder.append("extra VARCHAR(5000)\n")
        } else {
            stringBuilder.append("extra VARCHAR(5000),\n")
        }

        constraints.keys.forEach { fkName ->
            stringBuilder.append(
                    "CONSTRAINT fk_${constraints[fkName]?.references} FOREIGN KEY ($fkName) " +
                            "REFERENCES ${constraints[fkName]?.references}(${constraints[fkName]?.referencesOn})\n" +
                            "ON DELETE SET NULL\n"
            )
        }

        return stringBuilder.toString()
    }

    fun export(dir: String) {
        //iterate trough tables and write json
        database.mDb.transaction {
            for (table in mTables) {
                val tableName = table.name
                val file = FileWriter("$dir$tableName.json")
                val bf = BufferedWriter(file)
                val writer = JsonWriter(bf)
                val cursor = database.execQuery("select * from $tableName")
                        ?: throw IllegalStateException("Export failed: $tableName was unexpectedly empty")

                writer.beginArray()
                if (cursor.moveToFirst()) {
                    do {
                        var i = 0
                        writer.beginObject()
                        while (i < cursor.columnCount) {
                            val columnName = cursor.getColumnName(i)
                            if (columnName == "extra") {
                                val rawExtraJson = cursor.getString(i)
                                val extraJsonObject = gson.fromJson(rawExtraJson, JsonObject::class.java)
                                for (entry in extraJsonObject.entrySet()) {
                                    when {
                                        entry.value.isJsonNull -> writer.name(entry.key).nullValue()
                                        entry.value.isJsonObject -> writer.name(entry.key).jsonValue(gson.toJson(entry.value.asJsonObject))
                                        entry.value.isJsonArray -> writer.name(entry.key).jsonValue(gson.toJson(entry.value.asJsonArray))
                                        else -> writer.name(entry.key).value(entry.value.asString)
                                    }
                                }
                            } else {
                                if (table.columns[columnName]?.type == "BOOLEAN") {
                                    val entry = cursor.getInt(i)
                                    writer.name(columnName).value(entry != 0)
                                } else {
                                    if (cursor.isNull(i)) {
                                        writer.name(columnName).nullValue()
                                    } else {
                                        val entry = cursor.getString(i)
                                        log("$columnName : $entry")
                                        writer.name(columnName).value(entry)
                                    }
                                }
                            }
                            i++
                        }
                        writer.endObject()
                    } while (cursor.moveToNext())
                } else {
                    throw IllegalStateException("Export failed: $tableName was unexpectedly empty")
                }
                cursor.close()
                writer.endArray()
                writer.flush()
                writer.close()
            }
        }
    }

    data class Table(
            val name: String,
            val columns: Map<String, Column>,
            val constraints: Map<String, Constraint>,
            val manyOnConstraints: Map<String, ManyOnConstraint>
    )

    data class Constraint(
            val references: String?,
            val referencesOn: String?
    )

    data class ManyOnConstraint(
            val references: String?,
            val referencesOn: String?,
            val manyOn: String?
    )

    data class Column(
            val pk: Boolean?,
            val type: String
    )
}