package com.example.gamebooster

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier

@Composable
fun Root() {
    var tab by remember { mutableStateOf(0) }
    val tabs = listOf("Boost" to "⚡", "Games" to "🎮", "Clean" to "🧹", "Security" to "🛡", "Apps" to "📱")

    Scaffold(
        bottomBar = {
            NavigationBar {
                tabs.forEachIndexed { i, t ->
                    NavigationBarItem(
                        selected = tab == i,
                        onClick = { tab = i },
                        icon = { Text(t.second) },
                        label = { Text(t.first, maxLines = 1) }
                    )
                }
            }
        }
    ) { inner ->
        Box(Modifier.padding(inner).fillMaxSize()) {
            when (tab) {
                0 -> HomeScreen()
                1 -> GamesScreen()
                2 -> CleanScreen()
                3 -> SecurityScreen()
                else -> AppsScreen()
            }
        }
    }
}
