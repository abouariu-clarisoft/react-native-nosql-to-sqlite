package com.clarisoft.nosqltosqlite.libdb

import android.content.Context
import android.os.Environment
import net.sqlcipher.Cursor
import net.sqlcipher.database.SQLiteDatabase
import java.io.File
import kotlin.system.measureTimeMillis

class Database {
    lateinit var mDb: SQLiteDatabase

    fun destroy() {
        mDb.close()
    }

    fun openOrCreate(path: String, pass: String, applicationContext: Context) {
        SQLiteDatabase.loadLibs(applicationContext)
        mDb = SQLiteDatabase.openOrCreateDatabase(path, pass, null)
    }

    fun execSQL(sql: String) {
        mDb.rawExecSQL(sql)
    }

    fun execQuery(sql: String): Cursor? {
        return mDb.rawQuery(sql, arrayOf())
    }

}