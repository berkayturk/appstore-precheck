import FirebaseRemoteConfig
let reviewMode = remoteConfig["review_mode"].boolValue
if !reviewMode { showHiddenCasino() }
