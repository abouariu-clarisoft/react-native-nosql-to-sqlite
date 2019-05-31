package com.clarisoft.nosqltosqlite.libdb

import android.content.Context
import android.os.Environment
import android.util.Log
import com.facebook.react.bridge.Callback
import net.sqlcipher.database.SQLiteDatabase
import java.io.File
import java.util.concurrent.Executors
import kotlin.system.measureTimeMillis

private val IO_EXECUTOR = Executors.newSingleThreadExecutor()


fun log(s: String) {
    Log.d("whodb", s)
}

/**
 * Utility method to run blocks on a dedicated background thread, used for io/database work.
 */
fun runOnIoThread(f: () -> Unit) {
    IO_EXECUTOR.execute(f)
}


inline fun <T> SQLiteDatabase.transaction(
    body: SQLiteDatabase.() -> T
): T {
    beginTransaction()
    try {
        val result = body()
        setTransactionSuccessful()
        return result
    } finally {
        endTransaction()
    }
}

fun test(applicationContext: Context, progressCallback: Callback) {
    runOnIoThread {
        //        progressCallback.invoke("Creating database...")

        val db = Database()
        val dbFile = File(Environment.getExternalStorageDirectory().path + "/testdb.db")
        dbFile.mkdirs()
        dbFile.delete()
        log(dbFile.absolutePath)

        db.openOrCreate(dbFile.absolutePath, "1337", applicationContext)
        val dbController = DbController(Environment.getExternalStorageDirectory().path + "/_config.json", null, db)

        val rawSql = dbController.mapTablesToSqlString()
        db.execSQL(rawSql)
//        progressCallback.invoke("Importing data...")

        var debugString = ""
        val time = measureTimeMillis {
            debugString = dbController.importFromJson("whodb_big")
        }
        db.destroy()
        progressCallback.invoke("Done! $debugString in ${time / 1000}s")
    }
}

