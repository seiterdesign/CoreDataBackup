//
//  CoreDataBackupApp.swift
//  CoreDataBackup
//
//  Created by Moritz Seiter on 24.09.22.
//

import SwiftUI

@main
struct CoreDataBackupApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject var backupVM = BackupViewModel()

    var body: some Scene {
        WindowGroup {
            if backupVM.restoreMode {
                RestoreView(backupVM: backupVM)
            } else {
                ContentView(backupVM: backupVM)
                    .id(backupVM.viewID)
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
            }
        }
    }
}

struct RestoreView: View {
    
    @ObservedObject var backupVM: BackupViewModel
    
    var body: some View {
        VStack{
            Text("Restore Backup")
            ProgressView()
        }
        .onAppear{
            DispatchQueue.main.asyncAfter(deadline: .now() + 1){
                if let url = backupVM.selectedURL {
                    do{
                        try PersistenceController.shared.container.restorePersistentStore(from: url)
                    } catch {

                    }
                }
                PersistenceController.shared.resoredInit()
                backupVM.viewID = UUID()
                backupVM.restoreMode = false
            }
        }
    }
}


class BackupViewModel: ObservableObject {
    
    @Published var backups: [String]
    @Published var restoreMode: Bool = false
    @Published var selectedURL: URL?
    @Published var viewID: UUID = UUID()
    
    init(){
        backups = UserDefaults.standard.array(forKey: "backupsKey") as? [String] ?? []
    }
    
    func addBackup() {
        let url = newBackupURL()
        selectedURL = url
        backups = [url.description]
        UserDefaults.standard.set(backups, forKey: "backupsKey")
        do{
            try PersistenceController.shared.container.copyPersistentStores(to: url)
        } catch {
            
        }
    }
    
    func newBackupURL() -> URL {
        let exportPath = NSTemporaryDirectory() + "Backup\(Date().description).sqlite"
        let exportURL = URL(fileURLWithPath: exportPath)
        return exportURL
    }
}
