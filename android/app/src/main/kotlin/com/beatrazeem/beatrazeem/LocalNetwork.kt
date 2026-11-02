package com.beatrazeem.beatrazeem

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.net.wifi.WifiManager
import java.net.Inet4Address

/** Only Beatrazeem is bound to the selected Wi-Fi; other apps are unaffected. */
class LocalNetwork(context: Context) {
    private val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private var bound = false
    private val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private var wifiLock: WifiManager.WifiLock? = null

    fun prepareListener(): List<String> {
        release()
        val networks = listOfNotNull(connectivity.activeNetwork) + connectivity.allNetworks.toList()
        val wifi = networks.distinct().firstOrNull {
            val caps = connectivity.getNetworkCapabilities(it)
            caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true &&
                !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        } ?: error("Connect this phone to the creator’s hotspot in Android Wi-Fi settings, then join again.")
        val properties = connectivity.getLinkProperties(wifi)
            ?: error("Wi-Fi is still connecting. Please try again.")
        val gateways = properties.routes.mapNotNull { route ->
            val address = route.gateway
            if (address is Inet4Address && !address.isAnyLocalAddress) address.hostAddress else null
        }.toMutableSet()
        if (Build.VERSION.SDK_INT >= 30) properties.dhcpServerAddress?.hostAddress?.let { gateways.add(it) }
        check(connectivity.bindProcessToNetwork(wifi)) { "The Wi-Fi connection changed. Join again." }
        bound = true
        try {
            @Suppress("DEPRECATION")
            val lock = wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "Beatrazeem:Room")
            lock.setReferenceCounted(false)
            lock.acquire()
            wifiLock = lock
        } catch (_: Exception) { /* The room still works if this device denies a Wi-Fi lock. */ }
        return gateways.toList()
    }

    fun release() {
        if (wifiLock?.isHeld == true) wifiLock?.release()
        wifiLock = null
        if (bound) connectivity.bindProcessToNetwork(null)
        bound = false
    }
}
