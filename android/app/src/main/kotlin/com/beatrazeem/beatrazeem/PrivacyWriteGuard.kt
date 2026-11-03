package com.beatrazeem.beatrazeem

/**
 * SharedPreferences updates its process cache before commit reports disk success.
 * Keep that unconfirmed cache from granting consent after an Activity is recreated.
 * This object outlives Activities, and its lock also orders privacy reads/writes
 * submitted by the old and new Activity's separate workers.
 */
internal object PrivacyWriteGuard {
    private var unconfirmedWrite = false

    @Synchronized
    fun <T> read(receipt: () -> T?): T? = if (unconfirmedWrite) null else receipt()

    /** Only explicit consent replacement or local deletion can confirm a write. */
    @Synchronized
    fun commit(write: () -> Boolean): Boolean {
        unconfirmedWrite = true
        val committed = write()
        if (committed) unconfirmedWrite = false
        return committed
    }
}
