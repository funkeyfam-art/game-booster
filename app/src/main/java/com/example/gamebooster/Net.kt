package com.example.gamebooster

import java.net.InetSocketAddress
import java.net.Socket

object Net {
    /** TCP connect time to Cloudflare DNS in ms, or -1 if no internet. Call off the main thread. */
    fun pingMs(): Int {
        return try {
            val s = Socket()
            val t0 = System.nanoTime()
            s.connect(InetSocketAddress("1.1.1.1", 443), 1500)
            val ms = ((System.nanoTime() - t0) / 1_000_000).toInt()
            s.close()
            ms
        } catch (e: Exception) {
            -1
        }
    }
}
