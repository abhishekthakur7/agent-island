import SessionDomain

public enum CursorACPControlledSessionStoreOutcome: Sendable, Equatable {
    case recorded
    case alreadyRecorded
    case storageUnavailable(StorageFailureReason)
}
