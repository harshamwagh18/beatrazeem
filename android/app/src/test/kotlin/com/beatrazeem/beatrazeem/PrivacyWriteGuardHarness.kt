package com.beatrazeem.beatrazeem

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Models Android's memory-before-disk SharedPreferences commit semantics. */
fun main() {
    class Preferences {
        var cachedReceipt: String? = "previous receipt"
        fun commit(receipt: String?, diskSucceeded: Boolean): Boolean {
            cachedReceipt = receipt
            return diskSucceeded
        }
    }
    val preferences = Preferences()
    fun readFromActivity(): String? = PrivacyWriteGuard.read { preferences.cachedReceipt }
    var checks = 0
    fun verify(name: String, action: () -> Unit) {
        action()
        checks++
        println("PASS $name")
    }

    verify("confirmed storage is readable") {
        check(readFromActivity() == "previous receipt")
    }
    verify("failed disk commit cannot expose its already updated memory receipt") {
        check(!PrivacyWriteGuard.commit { preferences.commit("unsaved consent", false) })
        check(preferences.cachedReceipt == "unsaved consent")
        check(readFromActivity() == null)
    }
    verify("recreated Activity cannot trust the shared process cache") {
        val recreatedActivityReader = { readFromActivity() }
        check(recreatedActivityReader() == null)
        var touchedCache = false
        check(PrivacyWriteGuard.read { touchedCache = true; "unsaved consent" } == null)
        check(!touchedCache)
    }
    verify("repeated save failure stays blocked") {
        check(!PrivacyWriteGuard.commit { preferences.commit("second unsaved consent", false) })
        check(readFromActivity() == null)
    }
    verify("exception after cache mutation also stays blocked") {
        val failure = runCatching {
            PrivacyWriteGuard.commit {
                preferences.cachedReceipt = "interrupted consent"
                error("Simulated disk error")
            }
        }
        check(failure.isFailure)
        check(readFromActivity() == null)
    }
    verify("successful explicit retry restores access to the confirmed receipt") {
        check(PrivacyWriteGuard.commit { preferences.commit("confirmed consent", true) })
        check(readFromActivity() == "confirmed consent")
    }
    verify("failed deletion blocks stale cache and successful deletion clears the gate") {
        check(!PrivacyWriteGuard.commit { preferences.commit(null, false) })
        // Simulate another cache observation of the pre-deletion record.
        preferences.cachedReceipt = "stale receipt"
        check(readFromActivity() == null)
        check(PrivacyWriteGuard.commit { preferences.commit(null, true) })
        var readExecuted = false
        check(PrivacyWriteGuard.read { readExecuted = true; preferences.cachedReceipt } == null)
        check(readExecuted)
    }
    verify("read from a recreated Activity cannot race a pending failed write") {
        val writeEntered = CountDownLatch(1)
        val allowWriteToFinish = CountDownLatch(1)
        val readStarted = CountDownLatch(1)
        val readFinished = CountDownLatch(1)
        val threadFailure = AtomicReference<Throwable?>()
        val result = AtomicReference<String?>("not read")
        val writer = Thread {
            try {
                check(!PrivacyWriteGuard.commit {
                    preferences.cachedReceipt = "pending unsaved consent"
                    writeEntered.countDown()
                    check(allowWriteToFinish.await(5, TimeUnit.SECONDS))
                    false
                })
            } catch (failure: Throwable) { threadFailure.set(failure) }
        }
        val reader = Thread {
            try {
                readStarted.countDown()
                result.set(readFromActivity())
            } catch (failure: Throwable) { threadFailure.set(failure) }
            finally { readFinished.countDown() }
        }
        writer.start()
        check(writeEntered.await(5, TimeUnit.SECONDS))
        reader.start()
        check(readStarted.await(5, TimeUnit.SECONDS))
        try {
            check(!readFinished.await(50, TimeUnit.MILLISECONDS))
        } finally {
            allowWriteToFinish.countDown()
        }
        writer.join(5_000)
        reader.join(5_000)
        check(!writer.isAlive && !reader.isAlive)
        threadFailure.get()?.let { throw it }
        check(result.get() == null)
    }
    println("$checks privacy write checks passed")
}
