package dev.polkabind.example

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.*
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import dev.polkabind.doTransfer

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { PolkabindDemo() }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PolkabindDemo() {
    var destHex by remember { mutableStateOf(
        "0x8eaf04151687736326c9fea17e25fc5287613693c912909cb226aa4794f26a48"
    ) }
    var amountText by remember { mutableStateOf("1000000000000") }
    var status by remember { mutableStateOf("Ready") }

    Scaffold(topBar = { TopAppBar(title = { Text("Polkabind Demo") }) }) { p ->
        Column(Modifier.padding(p).padding(16.dp).fillMaxSize()) {
            Text("Transfer", style = MaterialTheme.typography.titleLarge)
            OutlinedTextField(
                value = destHex, onValueChange = { destHex = it },
                label = { Text("Destination hex") }, singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(8.dp))
            OutlinedTextField(
                value = amountText, onValueChange = { amountText = it },
                label = { Text("Amount") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                singleLine = true, modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(16.dp))
            Button(onClick = {
                // kick off a background thread for the blocking FFI call
                Thread {
                    runCatching {
                        val amt = amountText.toLongOrNull()
                            ?: throw IllegalArgumentException("Bad amount")
                        doTransfer(destHex, amt.toULong())
                    }.fold(
                        onSuccess  = { status = "✅ Success!" },
                        onFailure  = { status = "❌ ${it.message}" }
                    )
                }.start()
                status = "⏳ Sending…"
            }, modifier = Modifier.fillMaxWidth()) {
                Text("Send Transfer")
            }
            Spacer(Modifier.height(24.dp))
            Text("Status", style = MaterialTheme.typography.titleLarge)
            Text(
                text = status,
                color = if (status.startsWith("✅")) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.error
            )
        }
    }
}