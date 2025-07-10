//
//  ContentView.swift
//  PolkabindExample
//
//  Created by Wassim Mansouri on 10/07/2025.
//

import SwiftUI
import Polkabind      // the Swift wrapper target from your package

struct ContentView: View {
    @State private var destHex    = "0x8eaf04151687736326c9fea17e25fc5287613693c912909cb226aa4794f26a48"
    @State private var amountText = "1_000_000_000_000"
    @State private var status     = "Ready"

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Transfer Parameters")) {
                    TextField("Destination (hex)", text: $destHex)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Amount", text: $amountText)
                        .keyboardType(.numberPad)
                }
                Section {
                    Button("Send Transfer") {
                        Task {
                            do {
                                let amount = UInt64(amountText) ?? 0
                                try doTransfer(destHex: destHex, amount: amount)
                                status = "✅ Transfer succeeded!"
                            } catch {
                                status = "❌ \(error)"
                            }
                        }
                    }
                }
                Section(header: Text("Status")) {
                    Text(status)
                        .foregroundColor(status.hasPrefix("✅") ? .green : .red)
                }
            }
            .navigationTitle("Polkabind Transfer")
        }
    }
}
