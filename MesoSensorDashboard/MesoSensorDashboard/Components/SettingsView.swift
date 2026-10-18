//
//  SettingsView.swift
//  MesoSensorDashboard
//

import SwiftUI
import CoreBluetooth

// MARK: - Local UI Constants
private enum UIConstants {
    // Layout & Spacing
    static let cardPadding: CGFloat = 16
    static let cardCornerRadius: CGFloat = 16
    static let buttonCornerRadius: CGFloat = 6
    static let horizontalMargin: CGFloat = 20
    static let scrollPaddingTop: CGFloat = 16
    static let buttonHorizontalPadding: CGFloat = 12
    static let buttonHeight: CGFloat = 30
    static let buttonWidth: CGFloat = 72

    // Font Sizes
    static let labelFontSize: CGFloat = 15
    static let buttonFontSize: CGFloat = 13

    // Opacities
    static let disabledButtonOpacity: Double = 0.5

    // Strings & Formatting
    static let viewTitle = "Settings"
    static let pendantBaseText = "Pendant"
    static let pendantCombinedFormat = "%@ (%@)"
    static let statusConnected = "Connected"
    static let statusConnecting = "Connecting..."
    static let statusReadyForPairing = "Ready For Pairing"
    static let statusDisconnected = "Disconnected"
    static let buttonForget = "Forget"
    static let buttonPair = "Pair"
    static let pairedUUIDKey = "MesoNosePairedUUID"
}

struct SettingsView: View {
    @EnvironmentObject var bluetoothManager: BluetoothManager
    @AppStorage(UIConstants.pairedUUIDKey) private var pairedUUIDString: String = ""

    private var isPairedOrConnected: Bool {
        bluetoothManager.savedMesoNoseUUID != nil || bluetoothManager.mesoNosePeripheral?.state == .connected
    }

    private var settingsStatusText: String {
        if let nose = bluetoothManager.mesoNosePeripheral {
            switch nose.state {
            case .connected:
                return UIConstants.statusConnected
            case .connecting:
                return UIConstants.statusConnecting
            default:
                break
            }
        }

        if bluetoothManager.isPairingModeActive {
            return UIConstants.statusReadyForPairing
        } else {
            return UIConstants.statusDisconnected
        }
    }

    private var combinedPendantLabel: String {
        String(format: UIConstants.pendantCombinedFormat, UIConstants.pendantBaseText, settingsStatusText)
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                DashboardHeaderView(title: UIConstants.viewTitle)

                ScrollView {
                    VStack(spacing: UIConstants.cardPadding) {
                        // Pendant Device Card
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .center, spacing: 0) {
                                // Combined Label: "Pendant (<Status>)"
                                Text(combinedPendantLabel)
                                    .font(.system(size: UIConstants.labelFontSize, weight: .bold, design: .rounded))
                                    .foregroundColor(Color.appPrimaryText)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)

                                Spacer()

                                // Small Rectangular Action Button (White background, Black text)
                                Button(action: {
                                    withAnimation(.smooth) {
                                        if isPairedOrConnected {
                                            // Forget / Unpair Device
                                            bluetoothManager.disconnectMesoNose()
                                            bluetoothManager.savedMesoNoseUUID = nil
                                            pairedUUIDString = ""
                                        } else {
                                            // Start Pairing Scan
                                            bluetoothManager.startPairingMesoNose()
                                        }
                                    }
                                }) {
                                    Text(isPairedOrConnected ? UIConstants.buttonForget : UIConstants.buttonPair)
                                        .font(.system(size: UIConstants.buttonFontSize, weight: .bold, design: .rounded))
                                        .foregroundColor(Color.black)
                                        .frame(width: UIConstants.buttonWidth, height: UIConstants.buttonHeight)
                                        .background(Color.white)
                                        .cornerRadius(UIConstants.buttonCornerRadius)
                                }
                                .disabled(bluetoothManager.isPairingModeActive && !isPairedOrConnected)
                                .opacity((bluetoothManager.isPairingModeActive && !isPairedOrConnected) ? UIConstants.disabledButtonOpacity : 1.0)
                            }
                        }
                        .padding(UIConstants.cardPadding)
                        .background(Color.jadeiteTranslucent)
                        .cornerRadius(UIConstants.cardCornerRadius)
                    }
                    .padding(.horizontal, UIConstants.horizontalMargin)
                    .padding(.top, UIConstants.scrollPaddingTop)
                }
            }
        }
    }
}
