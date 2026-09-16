package com.tenseitech.doctornect

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // FlutterActivity is not a ComponentActivity, so enableEdgeToEdge() cannot be used.
        // Draw behind system bars; Flutter SystemChrome + SafeArea handle insets.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }
}
