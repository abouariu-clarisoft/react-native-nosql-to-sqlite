package com.clarisoft.nosqltosqlite

import android.database.Cursor
import android.os.Environment
import com.clarisoft.nosqltosqlite.libdb.*
import com.facebook.react.bridge.*
import java.io.File

class RNNosqlToSqliteModule(private val reactContext: ReactApplicationContext) : ReactContextBaseJavaModule(reactContext) {

    private lateinit var db: Database
    private lateinit var dbController: DbController

    @ReactMethod
    fun configureDatabaseWithName(name: String, encryptionKey: String, config: String, callback: Callback) {
        runOnIoThread {
            db = Database()
            val dbFile = File(Environment.getExternalStorageDirectory().path + "/$name")
            dbFile.mkdirs()
            dbFile.delete()
            log(dbFile.absolutePath)
            db.openOrCreate(dbFile.absolutePath, encryptionKey, reactContext)
            dbController = DbController(null, config, db)
            dbController.createConfigTables()
            callback.invoke()
        }
    }

    @ReactMethod
    fun importData(dataPath: String, callback: Callback) {
        runOnIoThread {
            callback.invoke(dbController.importFromJson(dataPath))
        }
    }

    @ReactMethod
    fun exportData(dir: String, callback: Callback) {
        runOnIoThread {
            dbController.export(Environment.getExternalStorageDirectory().path + "/") //TODO
            callback()
        }
    }

    @ReactMethod
    fun performSelect(query: String, callback: Callback) {
        runOnIoThread {
            val cursor = db.execQuery(query)
            if (cursor == null) {
                callback.invoke()
            } else {
                val toArrayList = cursor.toReactArray()
                callback.invoke(toArrayList)
            }
        }
    }

    /**
     *  Consumes and *closes* entire cursor, returns ReadableArray of WritebleMaps of (columnName -> value) entries
     */
    private fun Cursor.toReactArray(): ReadableArray {
        return Arguments.createArray().also { list ->
            if (moveToFirst()) {
                do {
                    list.pushMap(createMapFromResult(this))
                } while (moveToNext())
            }
        }.also {
            this.close()
            return it
        }
    }

    private val createMapFromResult: (Cursor) -> WritableMap = { cursor ->
        var i = 0
        val writableMap = Arguments.createMap()
        while (i < cursor.columnCount) {
            val columnName = cursor.getColumnName(i)
            val entry = cursor.getString(i)
            i++
            writableMap.putString(columnName, entry)
        }
        writableMap
    }

    @ReactMethod
    fun performUpdate(query: String, callback: Callback) {
        runOnIoThread {
            db.execQuery(query)
            callback()
        }
    }

    @ReactMethod
    fun closeDatabase() {
        runOnIoThread {
            db.destroy()
        }
    }

    @ReactMethod
    fun testMethod(progressCallback: Callback) {
        test(reactContext, progressCallback)
    }


    override fun getName(): String {
        return "RNNosqlToSqlite"
    }

}