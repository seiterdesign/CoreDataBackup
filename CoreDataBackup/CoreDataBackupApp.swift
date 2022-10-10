//
//  CoreDataBackupApp.swift
//  CoreDataBackup
//
//  Created by Moritz Seiter on 24.09.22.
//

import SwiftUI
import CoreData

@main
struct CoreDataBackupApp: App {
    
    @StateObject var backupVM = BackupViewModel()

    var body: some Scene {
        WindowGroup {
            if backupVM.restoreMode {
                RestoreView(backupVM: backupVM)
            } else {
                ContentView(backupVM: backupVM)
                    .id(backupVM.viewID)
                    .environment(\.managedObjectContext, backupVM.persistenceController.container.viewContext)
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
                do{
                    try PersistenceController.shared.container.persistentStoreCoordinator.restoreBackup()
                } catch {
                    backupVM.viewID = UUID()
                    backupVM.restoreMode = false
                }
                backupVM.viewID = UUID()
                backupVM.persistenceController = PersistenceController.shared
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
    @Published var persistenceController = PersistenceController.shared
    
    init(){
        backups = UserDefaults.standard.array(forKey: "backupsKey") as? [String] ?? []
    }
    
    func createBackup() {
        let storeCoordinator: NSPersistentStoreCoordinator = PersistenceController.shared.container.persistentStoreCoordinator
        do {
            try storeCoordinator.backupPersistentStore(atIndex: 0)
        } catch {
            print("Error backing up Core Data store: \(error)")
        }
    }
}
