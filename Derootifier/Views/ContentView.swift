//
//  ContentView.swift
//  Derootifier
//
//  Created by Анохин Юрий on 15.04.2023.
//

import SwiftUI
import FluidGradient

struct ContentView: View {
    let scriptPath = Bundle.main.path(forResource: "patch", ofType: "sh")!
    @AppStorage("firstLaunch") private var firstLaunch = true
    @State private var showingSheet = false
    @State private var selectedFile: URL?
    @State private var simpleTweak: Bool = false
    @State private var usingRootlessCompat: Bool = true
    @State private var requireDynamicPatches: Bool = false
    
    func resetPatches() {
        simpleTweak = false
        usingRootlessCompat = true
        requireDynamicPatches = false
    }
    
    var body: some View {
        
        let _ = NotificationCenter.default.addObserver(forName:Notification.Name("patcherFileOpen"), object: nil, queue: nil) { noti in
            NSLog("RootHidePatcher: patcherFileOpen: \(noti)")
            UIApplication.shared.keyWindow?.rootViewController?.presentedViewController?.dismiss(animated: true)
            selectedFile = noti.object as? URL
            resetPatches()
        }
        
        //NavigationView {
            VStack(spacing: 10) {
                
                if let debfile = selectedFile {
                    Text(debfile.lastPathComponent)
                        .padding(30)
                        .opacity(0.5)
                }
                
                Button("Select .deb file") {
                    UISelectionFeedbackGenerator().selectionChanged()
                    showingSheet.toggle()
                }
                .buttonStyle(TintedButton(color: .white, fullwidth: true))
                .padding(5)
                .padding(.leading, 50)
                .padding(.trailing, 50)
                .opacity(selectedFile==nil ? 1 : 0.5)
                
                if let debfile = selectedFile {
                    Button("Convert .deb") {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        UIApplication.shared.alert(title: NSLocalizedString("Converting...", comment: ""), body: NSLocalizedString("Please wait", comment: ""), withButton: false)
                        DispatchQueue.global().async {
                            
                            let name = debfile.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "iphoneos-arm64", with: "-a-r-c-h-").replacingOccurrences(of: "iphoneos-arm", with: "-a-r-c-h-").replacingOccurrences(of: "-a-r-c-h-", with: "iphoneos-arm64e")
                            
                            let output = URL.init(fileURLWithPath: "/var/mobile/RootHidePatcher/\(name).deb")
                            
                            var patch=""
                            if usingRootlessCompat { patch="AutoPatches" } else if requireDynamicPatches { patch="DynamicPatches" }
                            DispatchQueue.main.async {
                                UIApplication.shared.isIdleTimerDisabled = true
                            }
                            let (exitCode,outputAux) = repackDeb(scriptPath: scriptPath, debURL: debfile, outputURL: output, patch: patch)
                            DispatchQueue.main.async {
                                UIApplication.shared.isIdleTimerDisabled = false
                            }
                            
                            DispatchQueue.main.async {
                                UIApplication.shared.dismissAlert(animated: false) {
                                    if exitCode != 0 {
                                        UIApplication.shared.alert(title: String(format: NSLocalizedString("Error(%d)", comment: ""), exitCode), body: outputAux)
                                        return
                                    }
                                    resetPatches()
                                    selectedFile = nil

                                    let alert = UIAlertController(title: NSLocalizedString("Done", comment: ""), message: outputAux, preferredStyle: .alert)
                                    if IsAppAvailable("org.coolstar.SileoStore") {
                                        alert.addAction(.init(title: NSLocalizedString("->Sileo", comment: ""), style: .default, handler: { _ in
                                            ShareFileToApp("org.coolstar.SileoStore", jbroot(output.path))
                                        }))
                                    } else if IsAppAvailable("xyz.willy.Zebra") {
                                        alert.addAction(.init(title: NSLocalizedString("->Zebra", comment: ""), style: .default, handler: { _ in
                                            ShareFileToApp("xyz.willy.Zebra", jbroot(output.path))
                                        }))
                                    }

                                    alert.addAction(.init(title: NSLocalizedString("->Share", comment: ""), style: .default, handler: { _ in
                                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                        checkFileMngrs(path: output.path)
                                    }))
                                    UIApplication.shared.present(alert: alert)
                                }
                            }
                        }
                    }
                    .buttonStyle(TintedButton(color: .white, fullwidth: true))
                    .padding(30)
                    .disabled(!simpleTweak && !usingRootlessCompat && !requireDynamicPatches)
                }
                
                
                if (selectedFile != nil) {
                    Toggle("Directly Convert Simple Tweaks", isOn: $simpleTweak)
                        .toggleStyle(SwitchToggleStyle(tint: Color.blue))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 300)
                        .padding(5)
                        .disabled(false).onChange(of: simpleTweak) { value in
                            if value {
                                usingRootlessCompat = false
                                requireDynamicPatches = false
                            }
                        }
                    Toggle("Rootless Compat Layer", isOn: $usingRootlessCompat)
                        .toggleStyle(SwitchToggleStyle(tint: Color.blue))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 300)
                        .padding(5)
                        .disabled(false).onChange(of: usingRootlessCompat) { value in
                            if value {
                                simpleTweak = false
                                requireDynamicPatches = false
                            }
                        }
                    Toggle("Require Dynamic Patches", isOn: $requireDynamicPatches)
                        .toggleStyle(SwitchToggleStyle(tint: Color.blue))
                        .foregroundColor(.white.opacity(0.3))
                        .frame(width: 300)
                        .padding(5)
                        .disabled(false).onChange(of: requireDynamicPatches) { value in
                            if value {
                                simpleTweak = false
                                usingRootlessCompat = false
                            }
                        }
                }
                
                NavigationLink(
                    destination: CreditsView(),
                    label: {
                        HStack {
//                            Text("Credits")
//                            Image(systemName: "chevron.right")
                            Text("Sileo will be automatically re-opened")
                        }
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 15))
                    }
                )
                .padding(50)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background (
                FluidGradient(blobs: [.green, .mint],
                              highlights: [.green, .mint],
                              speed: 0.5,
                              blur: 0.80)
                .background(.green)
            )
            .ignoresSafeArea()
            .onAppear {
                //                if firstLaunch {
                //                    UIApplication.shared.alert(title: "Warning", body: "Please make sure the following packages are installed: dpkg, file, odcctools, ldid (from Procursus).")
                //                    firstLaunch = false
                //                }
#if !targetEnvironment(simulator)
                folderCheck()
#endif
            }
            .sheet(isPresented: $showingSheet) {
                DocumentPicker(selectedFile: $selectedFile)
            }
        }
    //}
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
