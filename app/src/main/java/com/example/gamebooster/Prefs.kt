package com.example.gamebooster

import android.content.Context

object Prefs {
    const val MONITOR = "monitor"
    const val AUTO_BOOST = "auto_boost"
    const val AUTO_DND = "auto_dnd"
    const val OVERLAY = "overlay"
    const val THERMAL = "thermal"

    private fun sp(c: Context) = c.getSharedPreferences("gb_prefs", Context.MODE_PRIVATE)

    fun get(c: Context, key: String, def: Boolean): Boolean = sp(c).getBoolean(key, def)

    fun set(c: Context, key: String, value: Boolean) {
        sp(c).edit().putBoolean(key, value).apply()
    }

    fun pinned(c: Context): Set<String> =
        HashSet(sp(c).getStringSet("pinned", emptySet()) ?: emptySet())

    fun togglePinned(c: Context, pkg: String) {
        val s = HashSet(pinned(c))
        if (!s.remove(pkg)) s.add(pkg)
        sp(c).edit().putStringSet("pinned", s).apply()
    }
}
