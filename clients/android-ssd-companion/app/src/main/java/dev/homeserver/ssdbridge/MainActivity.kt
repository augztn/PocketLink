package dev.homeserver.ssdbridge

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.documentfile.provider.DocumentFile
import androidx.core.content.ContextCompat
import java.security.SecureRandom
import android.util.Base64

class MainActivity : Activity() {
    private val prefs by lazy { getSharedPreferences("ssd-bridge", MODE_PRIVATE) }
    private lateinit var status: TextView
    private lateinit var token: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 36, 32, 24)
        }
        status = TextView(this).apply { textSize = 16f }
        token = TextView(this).apply { textSize = 12f }
        layout.addView(TextView(this).apply {
            text = "HomeServer SSD Bridge\n\nGrant access to each USB partition. Android will remember these permissions."
            textSize = 19f
        })
        layout.addView(Button(this).apply {
            text = "Select USB Storage 1"
            setOnClickListener { chooseTree(1) }
        })
        layout.addView(Button(this).apply {
            text = "Select USB Storage 2"
            setOnClickListener { chooseTree(2) }
        })
        layout.addView(Button(this).apply {
            text = "Start local bridge"
            setOnClickListener {
                val intent = Intent(this@MainActivity, BridgeService::class.java)
                ContextCompat.startForegroundService(this@MainActivity, intent)
                updateStatus("Bridge start requested")
            }
        })
        layout.addView(Button(this).apply {
            text = "Stop local bridge"
            setOnClickListener {
                stopService(Intent(this@MainActivity, BridgeService::class.java))
                updateStatus("Bridge stopped")
            }
        })
        layout.addView(status)
        layout.addView(TextView(this).apply {
            text = "Local API: http://127.0.0.1:8765\nKeep this token private. The FastAPI backend will use it to authenticate to the bridge."
            textSize = 13f
        })
        layout.addView(token)
        setContentView(layout)
        ensureToken()
        updateStatus()
    }

    private fun chooseTree(slot: Int) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, slot)
    }

    @Deprecated("Legacy result callback retained for broad Android compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK || data?.data == null || requestCode !in 1..2) return
        val uri: Uri = data.data!!
        val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        try {
            contentResolver.takePersistableUriPermission(uri, flags)
            prefs.edit().putString("usb$requestCode", uri.toString()).apply()
            updateStatus("USB Storage $requestCode permission saved")
        } catch (error: SecurityException) {
            updateStatus("Could not persist permission: ${error.message}")
        }
    }

    private fun ensureToken(): String {
        val existing = prefs.getString("token", null)
        if (existing != null) return existing
        val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val generated = Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        prefs.edit().putString("token", generated).apply()
        return generated
    }

    private fun updateStatus(message: String? = null) {
        val one = prefs.getString("usb1", null)?.let {
            DocumentFile.fromTreeUri(this, Uri.parse(it))?.name ?: "Granted"
        } ?: "Not selected"
        val two = prefs.getString("usb2", null)?.let {
            DocumentFile.fromTreeUri(this, Uri.parse(it))?.name ?: "Granted"
        } ?: "Not selected"
        status.text = (message?.plus("\n") ?: "") + "USB Storage 1: $one\nUSB Storage 2: $two"
        token.text = "Bridge token: ${ensureToken()}"
    }
}
