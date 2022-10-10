//
//  Persistence.swift
//  CoreDataBackup
//
//  Created by Moritz Seiter on 24.09.22.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "CoreDataBackup")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}


/// Safely copies the specified `NSPersistentStore` to a temporary file.
/// Useful for backups.
///
/// - Parameter index: The index of the persistent store in the coordinator's
///   `persistentStores` array. Passing an index that doesn't exist will trap.
///
/// - Returns: The URL of the backup file, wrapped in a TemporaryFile instance
///   for easy deletion.
extension NSPersistentStoreCoordinator {
    func backupPersistentStore(atIndex index: Int) throws {
        // Inspiration: https://stackoverflow.com/a/22672386
        // Documentation for NSPersistentStoreCoordinate.migratePersistentStore:
        // "After invocation of this method, the specified [source] store is
        // removed from the coordinator and thus no longer a useful reference."
        // => Strategy:
        // 1. Create a new "intermediate" NSPersistentStoreCoordinator and add
        //    the original store file.
        // 2. Use this new PSC to migrate to a new file URL.
        // 3. Drop all reference to the intermediate PSC.
        precondition(persistentStores.indices.contains(index), "Index \(index) doesn't exist in persistentStores array")
        let sourceStore = persistentStores[index]
        let backupCoordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)

        let intermediateStoreOptions = (sourceStore.options ?? [:])
            .merging([NSReadOnlyPersistentStoreOption: true],
                     uniquingKeysWith: { $1 })
        let intermediateStore = try backupCoordinator.addPersistentStore(
            ofType: sourceStore.type,
            configurationName: sourceStore.configurationName,
            at: sourceStore.url,
            options: intermediateStoreOptions
        )

        let backupStoreOptions: [AnyHashable: Any] = [
            NSReadOnlyPersistentStoreOption: true,
            // Disable write-ahead logging. Benefit: the entire store will be
            // contained in a single file. No need to handle -wal/-shm files.
            // https://developer.apple.com/library/content/qa/qa1809/_index.html
            NSSQLitePragmasOption: ["journal_mode": "DELETE"],
            // Minimize file size
            NSSQLiteManualVacuumOption: true,
            ]

        // Filename format: basename-date.sqlite
        // E.g. "MyStore-20180221T200731.sqlite" (time is in UTC)
        func makeFilename() -> String {
            let basename = sourceStore.url?.deletingPathExtension().lastPathComponent ?? "store-backup"
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
            let dateString = dateFormatter.string(from: Date())
            return "\(basename)-\(dateString).sqlite"
        }
        
        let backupFilename = makeFilename()
        UserDefaults.standard.set(backupFilename, forKey: "backupName")
        guard let backupPath = getBackupPath(name: backupFilename) else {
            return
        }
        
        do{
            
            try backupCoordinator.migratePersistentStore(intermediateStore, to: backupPath, options: backupStoreOptions, withType: NSSQLiteStoreType)
        } catch {
            print("Could not Migrate intermediate Store \(error.localizedDescription)")
        }
        
    }
    enum CopyPersistentStoreErrors: Error {
            case invalidDestination(String)
            case destinationError(String)
            case destinationNotRemoved(String)
            case copyStoreError(String)
            case invalidSource(String)
        }
        
        /// Restore backup persistent stores located in the directory referenced by `backupURL`.
        ///
        /// **Be very careful with this**. To restore a persistent store, the current persistent store must be removed from the container. When that happens, **all currently loaded Core Data objects** will become invalid. Using them after restoring will cause your app to crash. When calling this method you **must** ensure that you do not continue to use any previously fetched managed objects or existing fetched results controllers. **If this method does not throw, that does not mean your app is safe.** You need to take extra steps to prevent crashes. The details vary depending on the nature of your app.
        /// - Parameter backupURL: A file URL containing backup copies of all currently loaded persistent stores.
        /// - Throws: `CopyPersistentStoreError` in various situations.
        /// - Returns: Nothing. If no errors are thrown, the restore is complete.
        func restoreBackup() throws -> Void {
            guard let backupName = UserDefaults.standard.object(forKey: "backupName") as? String else {
                throw CopyPersistentStoreErrors.invalidSource("Could not get backup name")
            }
            guard
                let backupStoreURL = getBackupPath(name: backupName),
                FileManager.default.fileExists(atPath: backupStoreURL.path)
            else {
                throw CopyPersistentStoreErrors.invalidSource("Backup URL Path is invalid")
            }

            guard let loadedStoreURL = persistentStores[0].url else {
                throw CopyPersistentStoreErrors.invalidDestination("Loded Persistent Store URL not found")
            }
            let privateConfiguration = NSPersistentStoreDescription(url: loadedStoreURL)
            
            
//            guard FileManager.default.fileExists(atPath: backupURLpath) else {
//                throw CopyPersistentStoreErrors.invalidSource("Missing backup store for \(backupURLpath)")
//            }
            
            do {
                try replacePersistentStore(at: loadedStoreURL, withPersistentStoreFrom: backupStoreURL, type: .sqlite)
            } catch {
                print("Error replacing store: \(error)")
                throw CopyPersistentStoreErrors.copyStoreError("Could not replace persistent store")
            }
            // Add the backup store at its current location
            PersistenceController.shared.container.persistentStoreCoordinator.addPersistentStore(with: privateConfiguration) { config, error in
                print("Restore complete")
            }
        }
}


func getBackupPath(name: String) -> URL? {
    guard
        let path = FileManager
            .default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(name)
    else {
        print("Error getting Backup path")
        return nil
    }
    return path
}
