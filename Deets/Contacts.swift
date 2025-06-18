import Contacts
import Foundation
import FoundationModels
import OSLog

private let log = Logger.service("contacts")

private let contactKeys =
    [
        CNContactTypeKey,
        CNContactGivenNameKey,
        CNContactFamilyNameKey,
        CNContactBirthdayKey,
        CNContactOrganizationNameKey,
        CNContactJobTitleKey,
        CNContactPhoneNumbersKey,
        CNContactEmailAddressesKey,
        CNContactInstantMessageAddressesKey,
        CNContactSocialProfilesKey,
        CNContactUrlAddressesKey,
        CNContactPostalAddressesKey,
        CNContactRelationsKey,
    ] as [CNKeyDescriptor]

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
class ContactsService: Service {
    let name = "Contacts"
    let description = "Access and manage contacts"
    var isEnabled = false
    
    private let contactStore = CNContactStore()

    static let shared = ContactsService()

    var isActivated: Bool {
        get async {
            let status = CNContactStore.authorizationStatus(for: .contacts)
            return status == .authorized
        }
    }

    func activate() async throws {
        log.debug("Activating contacts service")
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized:
            log.debug("Contacts access authorized")
            isEnabled = true
            return
        case .denied:
            log.error("Contacts access denied")
            throw ContactsError.accessDenied
        case .restricted:
            log.error("Contacts access restricted")
            throw ContactsError.accessDenied
        case .notDetermined:
            log.debug("Requesting contacts access")
            let granted = try await contactStore.requestAccess(for: .contacts)
            isEnabled = granted
        @unknown default:
            log.error("Unknown contacts authorization status")
            throw ContactsError.unknown
        }
    }
    
    var tools: [any Tool] {
        [
            ContactsMeTool(),
            ContactsSearchTool(),
            ContactsUpdateTool(),
            ContactsCreateTool()
        ]
    }
}

// MARK: - Tool Implementations

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
private struct ContactsMeTool: Tool {
    let name = "contacts_me"
    let description = "Get contact information about the user, including name, phone number, email, birthday, relations, address, online presence, and occupation. Always run this tool when the user asks a question that requires personal information about themselves."
    
    @Generable
    struct Arguments {
        @Guide(description: "this is the name of the contact to look for,")
        let contactName: String?
        
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        let eventStore = CNContactStore()
        let contact = try eventStore.unifiedMeContactWithKeys(toFetch: contactKeys)
        
        let contactInfo = ContactInfo(from: contact)
        
        let jsonData = try JSONEncoder().encode(contactInfo)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        return ToolOutput(jsonString)
    }
}

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
private struct ContactsSearchTool: Tool {
    let name = "contacts_search"
    let description = "Search contacts by name, phone number, and/or email"
    
    @Generable
    struct Arguments {
        @Guide(description: "Name to search for")
        let name: String?
        
        @Guide(description: "Phone number to search for")
        let phone: String?
        
        @Guide(description: "Email address to search for")
        let email: String?
        
        init(name: String? = nil, phone: String? = nil, email: String? = nil) {
            self.name = name
            self.phone = phone
            self.email = email
        }
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        let contactStore = CNContactStore()
        var predicates: [NSPredicate] = []

        if let name = arguments.name {
            let normalizedName = name.trimmingCharacters(in: .whitespaces)
            if !normalizedName.isEmpty {
                predicates.append(CNContact.predicateForContacts(matchingName: normalizedName))
            }
        }

        if let phone = arguments.phone {
            let phoneNumber = CNPhoneNumber(stringValue: phone)
            predicates.append(CNContact.predicateForContacts(matching: phoneNumber))
        }

        if let email = arguments.email {
            let normalizedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
            if !normalizedEmail.isEmpty {
                predicates.append(
                    CNContact.predicateForContacts(matchingEmailAddress: normalizedEmail))
            }
        }

        guard !predicates.isEmpty else {
            throw ContactsError.invalidArguments
        }

        // Combine predicates with AND if multiple criteria are provided
        let finalPredicate =
            predicates.count == 1
            ? predicates[0]
            : NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        let contacts = try contactStore.unifiedContacts(
            matching: finalPredicate,
            keysToFetch: contactKeys
        )

        let contactInfos = contacts.map { ContactInfo(from: $0) }
        
        let jsonData = try JSONEncoder().encode(contactInfos)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        
        return ToolOutput(jsonString)
    }
}

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
private struct ContactsUpdateTool: Tool {
    let name = "contacts_update"
    let description = "Update an existing contact's information. Only provide values for properties that need to be changed; omit any properties that should remain unchanged."
    
    @Generable
    struct Arguments {
        @Guide(description: "Unique identifier of the contact to update")
        let identifier: String
        
        @Guide(description: "Given name")
        let givenName: String?
        
        @Guide(description: "Family name")
        let familyName: String?
        
        @Guide(description: "Organization name")
        let organizationName: String?
        
        @Guide(description: "Job title")
        let jobTitle: String?
        
        @Guide(description: "Phone numbers")
        let phoneNumbers: ContactPhoneNumbers?
        
        @Guide(description: "Email addresses")
        let emailAddresses: ContactEmailAddresses?
        
        @Guide(description: "Postal addresses")
        let postalAddresses: ContactPostalAddresses?
        
        @Guide(description: "Birthday information")
        let birthday: ContactBirthday?
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        let contactStore = CNContactStore()
        
        // Fetch the mutable copy of the contact
        let predicate = CNContact.predicateForContacts(withIdentifiers: [arguments.identifier])
        let contact = try contactStore.unifiedContacts(matching: predicate, keysToFetch: contactKeys)
            .first?
            .mutableCopy() as? CNMutableContact

        guard let updatedContact = contact else {
            throw ContactsError.contactNotFound
        }

        // Update properties
        if let givenName = arguments.givenName {
            updatedContact.givenName = givenName
        }
        if let familyName = arguments.familyName {
            updatedContact.familyName = familyName
        }
        if let organizationName = arguments.organizationName {
            updatedContact.organizationName = organizationName
        }
        if let jobTitle = arguments.jobTitle {
            updatedContact.jobTitle = jobTitle
        }
        
        // Update phone numbers
        if let phoneNumbers = arguments.phoneNumbers {
            updatedContact.phoneNumbers = phoneNumbers.toLabeledValues()
        }
        
        // Update email addresses
        if let emailAddresses = arguments.emailAddresses {
            updatedContact.emailAddresses = emailAddresses.toLabeledValues()
        }
        
        // Update postal addresses
        if let postalAddresses = arguments.postalAddresses {
            updatedContact.postalAddresses = postalAddresses.toLabeledValues()
        }
        
        // Update birthday
        if let birthday = arguments.birthday {
            updatedContact.birthday = birthday.toDateComponents()
        }

        // Create a save request
        let saveRequest = CNSaveRequest()
        saveRequest.update(updatedContact)

        // Save the changes
        try contactStore.execute(saveRequest)

        let contactInfo = ContactInfo(from: updatedContact)
        
        let jsonData = try JSONEncoder().encode(contactInfo)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        return ToolOutput(jsonString)
    }
}

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
private struct ContactsCreateTool: Tool {
    let name = "contacts_create"
    let description = "Create a new contact with the specified information."
    
    @Generable
    struct Arguments {
        @Guide(description: "Given name")
        let givenName: String
        
        @Guide(description: "Family name")
        let familyName: String?
        
        @Guide(description: "Organization name")
        let organizationName: String?
        
        @Guide(description: "Job title")
        let jobTitle: String?
        
        @Guide(description: "Phone numbers")
        let phoneNumbers: ContactPhoneNumbers?
        
        @Guide(description: "Email addresses")
        let emailAddresses: ContactEmailAddresses?
        
        @Guide(description: "Postal addresses")
        let postalAddresses: ContactPostalAddresses?
        
        @Guide(description: "Birthday information")
        let birthday: ContactBirthday?
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        let contactStore = CNContactStore()
        
        // Create and populate a new contact
        let newContact = CNMutableContact()
        newContact.givenName = arguments.givenName
        
        if let familyName = arguments.familyName {
            newContact.familyName = familyName
        }
        if let organizationName = arguments.organizationName {
            newContact.organizationName = organizationName
        }
        if let jobTitle = arguments.jobTitle {
            newContact.jobTitle = jobTitle
        }
        
        // Set phone numbers
        if let phoneNumbers = arguments.phoneNumbers {
            newContact.phoneNumbers = phoneNumbers.toLabeledValues()
        }
        
        // Set email addresses
        if let emailAddresses = arguments.emailAddresses {
            newContact.emailAddresses = emailAddresses.toLabeledValues()
        }
        
        // Set postal addresses
        if let postalAddresses = arguments.postalAddresses {
            newContact.postalAddresses = postalAddresses.toLabeledValues()
        }
        
        // Set birthday
        if let birthday = arguments.birthday {
            newContact.birthday = birthday.toDateComponents()
        }

        // Create a save request
        let saveRequest = CNSaveRequest()
        saveRequest.add(newContact, toContainerWithIdentifier: nil)

        // Execute the save request
        try contactStore.execute(saveRequest)

        let contactInfo = ContactInfo(from: newContact)
        
        let jsonData = try JSONEncoder().encode(contactInfo)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        return ToolOutput(jsonString)
    }
}

// MARK: - Supporting Types
@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
struct ContactInfo: Codable {
    let identifier: String
    let givenName: String?
    let familyName: String?
    let organizationName: String?
    let jobTitle: String?
    let phoneNumbers: [String: String]?
    let emailAddresses: [String: String]?
    let postalAddresses: [String: ContactAddress]?
    let birthday: ContactBirthday?
    
    init(from contact: CNContact) {
        self.identifier = contact.identifier
        self.givenName = contact.givenName.isEmpty ? nil : contact.givenName
        self.familyName = contact.familyName.isEmpty ? nil : contact.familyName
        self.organizationName = contact.organizationName.isEmpty ? nil : contact.organizationName
        self.jobTitle = contact.jobTitle.isEmpty ? nil : contact.jobTitle
        
        // Phone numbers
        if !contact.phoneNumbers.isEmpty {
            var phones: [String: String] = [:]
            for phoneNumber in contact.phoneNumbers {
                let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: phoneNumber.label ?? "")
                phones[label] = phoneNumber.value.stringValue
            }
            self.phoneNumbers = phones
        } else {
            self.phoneNumbers = nil
        }
        
        // Email addresses
        if !contact.emailAddresses.isEmpty {
            var emails: [String: String] = [:]
            for emailAddress in contact.emailAddresses {
                let label = CNLabeledValue<NSString>.localizedString(forLabel: emailAddress.label ?? "")
                emails[label] = emailAddress.value as String
            }
            self.emailAddresses = emails
        } else {
            self.emailAddresses = nil
        }
        
        // Postal addresses
        if !contact.postalAddresses.isEmpty {
            var addresses: [String: ContactAddress] = [:]
            for postalAddress in contact.postalAddresses {
                let label = CNLabeledValue<CNPostalAddress>.localizedString(forLabel: postalAddress.label ?? "")
                addresses[label] = ContactAddress(from: postalAddress.value)
            }
            self.postalAddresses = addresses
        } else {
            self.postalAddresses = nil
        }
        
        // Birthday
        if let birthday = contact.birthday {
            self.birthday = ContactBirthday(from: birthday)
        } else {
            self.birthday = nil
        }
    }
}

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@Generable
struct ContactPhoneNumbers: Codable {
    @Guide(description: "Mobile phone number")
    let mobile: String?
    
    @Guide(description: "Work phone number")
    let work: String?
    
    @Guide(description: "Home phone number")
    let home: String?
    
    func toLabeledValues() -> [CNLabeledValue<CNPhoneNumber>] {
        var values: [CNLabeledValue<CNPhoneNumber>] = []
        
        if let mobile = mobile, !mobile.isEmpty {
            values.append(CNLabeledValue(
                label: CNLabelPhoneNumberMobile,
                value: CNPhoneNumber(stringValue: mobile)
            ))
        }
        
        if let work = work, !work.isEmpty {
            values.append(CNLabeledValue(
                label: CNLabelWork,
                value: CNPhoneNumber(stringValue: work)
            ))
        }
        
        if let home = home, !home.isEmpty {
            values.append(CNLabeledValue(
                label: CNLabelHome,
                value: CNPhoneNumber(stringValue: home)
            ))
        }
        
        return values
    }
}

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@Generable
struct ContactEmailAddresses: Codable {
    @Guide(description: "Work email address")
    let work: String?
    
    @Guide(description: "Home email address")
    let home: String?
    
    func toLabeledValues() -> [CNLabeledValue<NSString>] {
        var values: [CNLabeledValue<NSString>] = []
        
        if let work = work, !work.isEmpty {
            values.append(CNLabeledValue(
                label: CNLabelWork,
                value: work as NSString
            ))
        }
        
        if let home = home, !home.isEmpty {
            values.append(CNLabeledValue(
                label: CNLabelHome,
                value: home as NSString
            ))
        }
        
        return values
    }
}

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@Generable
struct ContactAddress: Codable {
    @Guide(description: "Street address")
    let street: String?
    
    @Guide(description: "City")
    let city: String?
    
    @Guide(description: "State or province")
    let state: String?
    
    @Guide(description: "Postal code")
    let postalCode: String?
    
    @Guide(description: "Country")
    let country: String?
    
    init(from postalAddress: CNPostalAddress) {
        self.street = postalAddress.street.isEmpty ? nil : postalAddress.street
        self.city = postalAddress.city.isEmpty ? nil : postalAddress.city
        self.state = postalAddress.state.isEmpty ? nil : postalAddress.state
        self.postalCode = postalAddress.postalCode.isEmpty ? nil : postalAddress.postalCode
        self.country = postalAddress.country.isEmpty ? nil : postalAddress.country
    }
}

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@Generable
struct ContactPostalAddresses: Codable {
    @Guide(description: "Work address")
    let work: ContactAddress?
    
    @Guide(description: "Home address")
    let home: ContactAddress?
    
    func toLabeledValues() -> [CNLabeledValue<CNPostalAddress>] {
        var values: [CNLabeledValue<CNPostalAddress>] = []
        
        if let work = work {
            let postalAddress = CNMutablePostalAddress()
            if let street = work.street { postalAddress.street = street }
            if let city = work.city { postalAddress.city = city }
            if let state = work.state { postalAddress.state = state }
            if let postalCode = work.postalCode { postalAddress.postalCode = postalCode }
            if let country = work.country { postalAddress.country = country }
            
            values.append(CNLabeledValue(
                label: CNLabelWork,
                value: postalAddress
            ))
        }
        
        if let home = home {
            let postalAddress = CNMutablePostalAddress()
            if let street = home.street { postalAddress.street = street }
            if let city = home.city { postalAddress.city = city }
            if let state = home.state { postalAddress.state = state }
            if let postalCode = home.postalCode { postalAddress.postalCode = postalCode }
            if let country = home.country { postalAddress.country = country }
            
            values.append(CNLabeledValue(
                label: CNLabelHome,
                value: postalAddress
            ))
        }
        
        return values
    }
}

@available(macOS 26.0, iOS 18.0, watchOS 11.0, tvOS 18.0, *)
@Generable
struct ContactBirthday: Codable {
    @Guide(description: "Day of birth (1-31)")
    let day: Int
    
    @Guide(description: "Month of birth (1-12)")
    let month: Int
    
    @Guide(description: "Year of birth")
    let year: Int?
    
    init(from dateComponents: DateComponents) {
        self.day = dateComponents.day ?? 1
        self.month = dateComponents.month ?? 1
        self.year = dateComponents.year
    }
    
    func toDateComponents() -> DateComponents {
        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year
        return components
    }
}

enum ContactsError: Error {
    case accessDenied
    case invalidArguments
    case contactNotFound
    case unknown
}
