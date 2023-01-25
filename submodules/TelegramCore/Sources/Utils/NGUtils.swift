import Foundation

//  MARK: Nicegram Translate

private let savedTranslationTargetLanguageKey = "ng:savedTranslationTargetLanguage"

public func getSavedTranslationTargetLanguage() -> String? {
    return UserDefaults.standard.string(forKey: savedTranslationTargetLanguageKey)
}

public func setSavedTranslationTargetLanguage(code: String) {
    UserDefaults.standard.set(code, forKey: savedTranslationTargetLanguageKey)
}
