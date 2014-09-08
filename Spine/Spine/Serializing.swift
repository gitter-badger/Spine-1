//
//  Mapping.swift
//  Spine
//
//  Created by Ward van Teijlingen on 23-08-14.
//  Copyright (c) 2014 Ward van Teijlingen. All rights reserved.
//

import UIKit
import SwiftyJSON

typealias DeserializationResult = (store: ResourceStore?, error: NSError?)

/**
 *  A ResourceClassMap contains information about how resource types
 *  should be mapped to Resource classes.

 *  Each resource type is mapped to one specific Resource subclass.
 */
struct ResourceClassMap {

	/// The registered resource type/class pairs.
	private var registeredClasses: [String: Resource.Type] = [:]
	
	/**
	 Register a Resource subclass.
	 Example: `classMap.register(User.self)`

	 :param: type The Type of the subclass to register.
	 */
	mutating func registerClass(type: Resource.Type) {
		let instance = type()
		self.registeredClasses[instance.resourceType] = type
	}
	
	/**
	 Unregister a Resource subclass. If the type was not prevously registered, nothing happens.
	 Example: `classMap.unregister(User.self)`

	 :param: type The Type of the subclass to unregister.
	 */
	mutating func unregisterClass(type: Resource.Type) {
		let instance = type()
		self.registeredClasses[instance.resourceType] = nil
	}
	
	/**
	 Returns the Resource.Type into which a resource with the given type should be mapped.

	 :param: resourceType The resource type for which to return the matching class.

	 :returns: The Resource.Type that matches the given resource type.
	 */
	func classForResourceType(resourceType: String) -> Resource.Type {
		return registeredClasses[resourceType]!
	}
	
	/**
	 *  Returns the Resource.Type into which a resource with the given type should be mapped.
	 */
	subscript(resourceType: String) -> Resource.Type {
		return self.classForResourceType(resourceType)
	}
}


// MARK: -

/**
 *  The serializer is responsible for serializing and deserialing resources.
 *  It stores information about the Resource classes using a ResourceClassMap
 *  and uses SerializationOperations and DeserialisationOperations for (de)serializing.
 */
class Serializer {

	/// The class map that holds information about resource type/class mapping.
	private var classMap: ResourceClassMap = ResourceClassMap()
	
	
	//MARK: Class mapping
	
	/**
	 Register a Resource subclass with this serializer.
	 Example: `classMap.register(User.self)`

	 :param: type The Type of the subclass to register.
	 */
	func registerClass(type: Resource.Type) {
		self.classMap.registerClass(type)
	}
	
	/**
	 Unregister a Resource subclass from this serializer. If the type was not prevously registered, nothing happens.
	 Example: `classMap.unregister(User.self)`

	 :param: type The Type of the subclass to unregister.
	 */
	func unregisterClass(type: Resource.Type) {
		self.classMap.unregisterClass(type)
	}
	
	/**
	 Returns the Resource.Type into which a resource with the given type should be mapped.

	 :param: resourceType The resource type for which to return the matching class.

	 :returns: The Resource.Type that matches the given resource type.
	 */
	func classNameForResourceType(resourceType: String) -> Resource.Type {
		return self.classMap[resourceType]
	}
	
	
	// MARK: Serializing

	/**
	 Deserializes the given data into a SerializationResult. This is a thin wrapper around
	 a DeserializeOperation that does the actual deserialization.

	 :param: data The data to deserialize.

	 :returns: A DeserializationResult that contains either a ResourceStore or an error.
	 */
	func deserializeData(data: NSData) -> DeserializationResult {
		let mappingOperation = DeserializeOperation(data: data, classMap: self.classMap)
		mappingOperation.start()
		return mappingOperation.result!
	}

	/**
	 Deserializes the given data into a SerializationResult. This is a thin wrapper around
	 a DeserializeOperation that does the actual deserialization.

	 Use this method if you want to deserialize onto existing Resource instances. Otherwise, use
	 the regular `deserializeData` method.

	 :param: data  The data to deserialize.
	 :param: store A ResourceStore that contains Resource instances onto which data will be deserialize.

	 :returns: A DeserializationResult that contains either a ResourceStore or an error.
	 */

	func deserializeData(data: NSData, usingStore store: ResourceStore) -> DeserializationResult {
		let mappingOperation = DeserializeOperation(data: data, store: store, classMap: self.classMap)
		mappingOperation.start()
		return mappingOperation.result!
	}
	

	/**
	 Deserializes the given data into an NSError. Use this method if the server response is not in the
	 200 successful range.

	 The error returned will contain the error code specified in the `error` section of the response.
	 If no error code is available, the given HTTP response status code will be used instead.
	 If the `error` section contains a `title` key, it's value will be used for the NSLocalizedDescriptionKey.

	 :param: data           The data to deserialize.
	 :param: responseStatus The HTTP response status which will be used when an error code is absent in the data.

	 :returns: A NSError deserialized from the given data.
	 */
	func deserializeError(data: NSData, withResonseStatus responseStatus: Int) -> NSError {
		let JSON = JSONValue(data as NSData!)
		
		let code = JSON["errors"][0]["id"].integer ?? responseStatus
		
		var userInfo: [String : AnyObject]?
		
		if let errorTitle = JSON["errors"][0]["title"].string {
			userInfo = [NSLocalizedDescriptionKey: errorTitle]
		}
		
		return NSError(domain: SPINE_ERROR_DOMAIN, code: code, userInfo: userInfo)
	}

	/**
	 Serializes the given Resources into a multidimensional dictionary/array structure
	 that can be passed to NSJSONSerialization.

	 :param: resources The resources to serialize.

	 :returns: A multidimensional dictionary/array structure.
	 */
	func serializeResources(resources: [Resource]) -> [String: [[String: AnyObject]]] {
		let mappingOperation = SerializeOperation(resources: resources)
		mappingOperation.start()
		return mappingOperation.result!
	}
}


// MARK: -

/**
 *  A DeserializeOperation is responsible for deserializing a single server response.
 *  The serialized data is converted into Resource instances using a layered process.
 *
 *  This process is the inverse of that of the SerializeOperation.
 */
class DeserializeOperation: NSOperation {
	
	struct LinkTemplate {
		var resourceType: String
		var key: String
		var href: String?
		var type: String?
		
		init(compoundKey: String, href: String?, type: String?) {
			let compoundKeyComponents = compoundKey.componentsSeparatedByString(".")
			self.init(resourceType: compoundKeyComponents[0], key: compoundKeyComponents[1], href: href, type: type)
		}
		
		init(resourceType: String, key: String, href: String?, type: String?) {
			self.resourceType = resourceType
			self.key = key
			self.href = href
			self.type = type
		}
		
		func interpolatedURL(data: [String: String]) -> String {
			if let template = self.href {
				var interpolated: NSString = template as NSString
				
				for (key, value) in data {
					let templateSegment = "{\(self.resourceType).\(key)}"
					interpolated = (interpolated as NSString).stringByReplacingOccurrencesOfString(templateSegment, withString: value)
				}
				
				return interpolated
			}
			
			return ""
		}
		
		func interpolatedURL(data: [String: [String]]) -> String {
			var mappedData: [String: String] = [:]
			for (key, value) in data {
				mappedData[key] = (value as NSArray).componentsJoinedByString(",")
			}
			
			return self.interpolatedURL(mappedData)
		}
	}
	
	private var data: JSONValue
	private var store: ResourceStore
	private var classMap: ResourceClassMap
	
	private lazy var formatter = {
		Formatter()
	}()
	
	var result: DeserializationResult?
	
	init(data: NSData, classMap: ResourceClassMap) {
		self.data = JSONValue(data as NSData!)
		self.classMap = classMap
		self.store = ResourceStore()
		super.init()
	}
	
	init(data: NSData, store: ResourceStore, classMap: ResourceClassMap) {
		self.data = JSONValue(data as NSData!)
		self.classMap = classMap
		self.store = store
		super.init()
	}
	
	override func main() {		
		if (self.data.object == nil) {
			let error = NSError(domain: SPINE_ERROR_DOMAIN, code: 0, userInfo: [NSLocalizedDescriptionKey: "The given JSON representation was not as expected."])
			self.result = DeserializationResult(nil, error)
			return
		}
		
		for(resourceType: String, resourcesData: JSONValue) in self.data.object! {
			if resourceType == "linked" {
				for (linkedResourceType, linkedResources) in resourcesData.object! {
					for representation in linkedResources.array! {
						self.deserializeSingleRepresentation(representation, withResourceType: linkedResourceType)
					}
				}
			} else if let resources = resourcesData.array {
				for representation in resources {
					self.deserializeSingleRepresentation(representation, withResourceType: resourceType)
				}
			}
		}
		
		self.extractLinks(self.data)
		self.resolveRelations()
		
		self.result = DeserializationResult(self.store, nil)
	}

	/**
	Maps a single resource representation into a resource object of the given type.
	
	:param: representation The JSON representation of a single resource.
	:param: resourceType   The type of resource onto which to map the representation.
	*/
	private func deserializeSingleRepresentation(representation: JSONValue, withResourceType resourceType: String) {
		assert(representation.object != nil, "The given JSON representation was not of type 'object' (dictionary).")
		
		// Find existing resource in the store, or create a new resource.
		var resource: Resource
		var isExistingResource: Bool
		
		if let existingResource = self.store.resource(resourceType, identifier: representation["id"].string!) {
			resource = existingResource
			isExistingResource = true
		} else {
			resource = self.classMap[resourceType]() as Resource
			isExistingResource = false
		}

		// Extract data into resource
		self.extractID(representation, intoResource: resource)
		self.extractHref(representation, intoResource: resource)
		self.extractAttributes(representation, intoResource: resource)
		self.extractRelationships(representation, intoResource: resource)

		// Add resource to store if needed
		if !isExistingResource {
			self.store.add(resource)
		}
	}
	
	
	// MARK: Special attributes
	
	/**
	 Extracts the resource ID from the serialized data into the given resource.

	 :param: serializedData The data from which to extract the ID.
	 :param: resource       The resource into which to extract the ID.
	 */
	private func extractID(serializedData: JSONValue, intoResource resource: Resource) {
		if let ID = serializedData["id"].string {
			resource.resourceID = ID
		}
	}
	
	/**
	 Extracts the resource href from the serialized data into the given resource.

	 :param: serializedData The data from which to extract the href.
	 :param: resource       The resource into which to extract the href.
	 */
	private func extractHref(serializedData: JSONValue, intoResource resource: Resource) {
		if let href = serializedData["href"].string {
			resource.resourceLocation = href
		}
	}
	
	
	// MARK: Links
	
	private func extractLinks(serializedData: JSONValue) {
		if let links = serializedData["links"].object {

			// Loop through all links in the serialized data
			for (linkName, linkData) in links {
				let linkTemplate = LinkTemplate(compoundKey: linkName, href: linkData["href"].string, type: linkData["type"].string)
				
				// Loop through all resources for which this is a link
				for resource in self.store.resourcesWithName(linkTemplate.resourceType) {
					
					// Find existing link to augment or create a new link
					var augmentedLink = resource.links[linkTemplate.key] ?? ResourceLink()
					
					// Assign the interpolated href if a href wasn't specified already
					if augmentedLink.href == nil {
						augmentedLink.href = linkTemplate.interpolatedURL(["id": resource.resourceID!, linkTemplate.key: augmentedLink.joinedIDs])
					}
					
					// Assign the type if the a type wasn't specified already
					if augmentedLink.type == nil {
						augmentedLink.type = linkTemplate.type
					}
					
					resource.links[linkTemplate.key] = augmentedLink
				}
			}
		}
	}
	
	
	// MARK: Attributes

	/**
	 Extracts the attributes from the given data into the given resource.

	 This method loops over all the attributes in the passed resource, maps the attribute name
	 to the key for the serialized form and invokes `extractAttribute`. It then formats the extracted
	 attribute and sets the formatted value on the resource.

	 :param: serializedData The data from which to extract the attributes.
	 :param: resource       The resource into which to extract the attributes.
	 */
	private func extractAttributes(serializedData: JSONValue, intoResource resource: Resource) {
		for (attributeName, attribute) in resource.persistentAttributes {
			if attribute.isRelationship() {
				continue
			}
			
			let key = attribute.representationName ?? attributeName
			
			if let extractedValue: AnyObject = self.extractAttribute(serializedData, key: key) {
				let formattedValue: AnyObject = self.formatter.deserialize(extractedValue, ofType: attribute.type)
				resource.setValue(formattedValue, forKey: attributeName)
			}
		}
	}
	
	/**
	 Extracts the value for the given key from the passed serialized data.

	 :param: serializedData The data from which to extract the attribute.
	 :param: key            The key for which to extract the value from the data.

	 :returns: The extracted value or nil if no attribute with the given key was found in the data.
	 */
	private func extractAttribute(serializedData: JSONValue, key: String) -> AnyObject? {
		if let value: AnyObject = serializedData[key].any {
			return value
		}
		
		return nil
	}
	
	
	// MARK: Relationships
	
	/**
	 Extracts the relationships from the given data into the given resource.

	 This method loops over all the relationships in the passed resource, maps the relationship name
	 to the key for the serialized form and invokes `extractToOneRelationship` or `extractToManyRelationship`.
	 It then sets the extracted ResourceRelationship on the resource.

	 :param: serializedData The data from which to extract the relationships.
	 :param: resource       The resource into which to extract the relationships.
	 */
	private func extractRelationships(serializedData: JSONValue, intoResource resource: Resource) {
		for (attributeName, attribute) in resource.persistentAttributes {
			if !attribute.isRelationship() {
				continue
			}
			
			let key = attribute.representationName ?? attributeName
			
			switch attribute.type {
			case .ToOne:
				if let extractedRelationship = self.extractToOneRelationship(serializedData, key: key, resource: resource) {
					resource.links[attributeName] = extractedRelationship
				}
			case .ToMany:
				if let extractedRelationship = self.extractToManyRelationship(serializedData, key: key, resource: resource) {
					resource.links[attributeName] = extractedRelationship
				}
			default: ()
			}
		}
	}
	
	/**
	 Extracts the to-one relationship for the given key from the passed serialized data.
	
	 :param: serializedData The data from which to extract the relationship.
	 :param: key            The key for which to extract the relationship from the data.
	
	 :returns: The extracted relationship or nil if no relationship with the given key was found in the data.
	*/
	private func extractToOneRelationship(serializedData: JSONValue, key: String, resource: Resource) -> ResourceLink? {
		if let linkData = serializedData["links"][key].object {
			var href: String?, ID: String?, type: String?
			
			if linkData["href"] != nil {
				href = linkData["href"]!.string
			}
			
			if linkData["id"] != nil {
				ID = linkData["id"]!.string
			}
			
			if linkData["type"] != nil {
				type = linkData["type"]!.string
			}
			
			return ResourceLink(href: href, ID: ID, type: type)
		}
		
		return nil
	}
	
	/**
	 Extracts the to-many relationship for the given key from the passed serialized data.
	
	 :param: serializedData The data from which to extract the relationship.
	 :param: key            The key for which to extract the relationship from the data.
	
	 :returns: The extracted relationship or nil if no relationship with the given key was found in the data.
	*/
	private func extractToManyRelationship(serializedData: JSONValue, key: String, resource: Resource) -> ResourceLink? {
		if let linkData = serializedData["links"][key].object {
			var href: String?, IDs: [String]?, type: String?
			
			if linkData["href"] != nil {
				href = linkData["href"]!.string
			}
			
			if linkData["ids"] != nil {
				IDs = linkData["ids"]!.array!.map { return $0.string! }
			}
			
			if linkData["type"] != nil {
				type = linkData["type"]!.string
			}
		
			return ResourceLink(href: href, IDs: IDs, type: type)
		}
		
		return nil
	}
	
	/**
	 Resolves the relations of the resources in the store.
	*/
	private func resolveRelations() {
		for resource in self.store.allResources() {
			
			for (linkName: String, link: ResourceLink) in resource.links {
				let type = link.type ?? linkName
				
				if resource.persistentAttributes[linkName]!.type == ResourceAttribute.AttributeType.ToOne {
					
					// We can only resolve if an ID is known
					if let ID = link.IDs?.first {

						// Find target of relation in store
						if let targetResource = store.resource(type, identifier: ID) {
							resource.setValue(targetResource, forKey: linkName)
						} else {
							// Target resource was not found in store, create a placeholder
							let placeholderResource = self.classMap[type]() as Resource
							placeholderResource.resourceID = ID
							resource.setValue(placeholderResource, forKey: linkName)
						}
					}
				
				} else if resource.persistentAttributes[linkName]!.type == ResourceAttribute.AttributeType.ToMany {
					var targetResources: [Resource] = []
					
					// We can only resolve if IDs are known
					if let IDs = link.IDs {

						for ID in IDs {
							// Find target of relation in store
							if let targetResource = store.resource(type, identifier: ID) {
								targetResources.append(targetResource)
							} else {
								// Target resource was not found in store, create a placeholder
								let placeholderResource = self.classMap[type]() as Resource
								placeholderResource.resourceID = ID
								targetResources.append(placeholderResource)
							}
							
							resource.setValue(targetResources, forKey: linkName)
						}
					}
				}
			}
		}
	}
}


// MARK: -

/**
 *  A SerializeOperation is responsible for serializing resource into a multidimensional dictionary/array structure.
 *  The resouces are converted to their serialized form using a layered process.
 *
 *  This process is the inverse of that of the DeserializeOperation.
 */
class SerializeOperation: NSOperation {
	
	private let resources: [Resource]
	private let formatter = Formatter()
	
	var result: [String: [[String: AnyObject]]]?
	
	init(resources: [Resource]) {
		self.resources = resources
	}
	
	override func main() {
		var dictionary: [String: [[String: AnyObject]]] = [:]
		
		//Loop through all resources
		for resource in resources {
			var serializedData: [String: AnyObject] = [:]
			
			// Special attributes
			if let ID = resource.resourceID {
				self.addID(&serializedData, ID: ID)
			}
			
			self.addAttributes(&serializedData, resource: resource)
			self.addRelationships(&serializedData, resource: resource)
			
			//Add the resource representation to the root dictionary
			if dictionary[resource.resourceType] == nil {
				dictionary[resource.resourceType] = [serializedData]
			} else {
				dictionary[resource.resourceType]!.append(serializedData)
			}
		}
		
		self.result = dictionary
	}
	
	
	// MARK: Special attributes
	
	/**
	Adds the given ID to the passed serialized data.
	
	:param: serializedData The data to add the ID to.
	:param: ID             The ID to add.
	*/
	private func addID(inout serializedData: [String: AnyObject], ID: String) {
		serializedData["id"] = ID
	}
	
	
	// MARK: Attributes
	
	/**
	Adds the attributes of the the given resource to the passed serialized data.
	
	This method loops over all the attributes in the passed resource, maps the attribute name
	to the key for the serialized form and formats the value of the attribute. It then passes
	the key and value to the addAttribute method.
	
	:param: serializedData The data to add the attributes to.
	:param: resource       The resource whose attributes to add.
	*/
	private func addAttributes(inout serializedData: [String: AnyObject], resource: Resource) {
		for (attributeName, attribute) in resource.persistentAttributes {
			if attribute.isRelationship() {
				continue
			}
			
			let key = attribute.representationName ?? attributeName
			
			if let unformattedValue: AnyObject = resource.valueForKey(attributeName) {
				self.addAttribute(&serializedData, key: key, value: self.formatter.serialize(unformattedValue, ofType: attribute.type))
			} else {
				self.addAttribute(&serializedData, key: key, value: NSNull())
			}
		}
	}
	
	/**
	Adds the given key/value pair to the passed serialized data.
	
	:param: serializedData The data to add the key/value pair to.
	:param: key            The key to add to the serialized data.
	:param: value          The value to add to the serialized data.
	*/
	private func addAttribute(inout serializedData: [String: AnyObject], key: String, value: AnyObject) {
		serializedData[key] = value
	}
	
	
	// MARK: Relationships
	
	/**
	Adds the relationships of the the given resource to the passed serialized data.
	
	This method loops over all the relationships in the passed resource, maps the attribute name
	to the key for the serialized form and gets the related attributes It then passes the key and
	related resources to either the addToOneRelationship or addToManyRelationship method.
	
	
	:param: serializedData The data to add the relationships to.
	:param: resource       The resource whose relationships to add.
	*/
	private func addRelationships(inout serializedData: [String: AnyObject], resource: Resource) {
		for (attributeName, attribute) in resource.persistentAttributes {
			if !attribute.isRelationship() {
				continue
			}
			
			let key = attribute.representationName ?? attributeName

			switch attribute.type {
				case .ToOne:
					self.addToOneRelationship(&serializedData, key: key, relatedResource: resource.valueForKey(attributeName) as? Resource)
				case .ToMany:
					self.addToManyRelationship(&serializedData, key: key, relatedResources: resource.valueForKey(attributeName) as? [Resource])
				default: ()
			}
		}
	}
	
	/**
	Adds the given resource as a to to-one relationship to the serialized data.
	
	:param: serializedData  The data to add the related resource to.
	:param: key             The key to add to the serialized data.
	:param: relatedResource The related resource to add to the serialized data.
	*/
	private func addToOneRelationship(inout serializedData: [String: AnyObject], key: String, relatedResource: Resource?) {
		var linkData: AnyObject
		
		if let ID = relatedResource?.resourceID {
			linkData = ID
		} else {
			linkData = NSNull()
		}
		
		if serializedData["links"] == nil {
			serializedData["links"] = [key: linkData]
		} else {
			var links: [String: AnyObject] = serializedData["links"]! as [String: AnyObject]
			links[key] = linkData
			serializedData["links"] = links
		}
	}
	
	/**
	Adds the given resources as a to to-many relationship to the serialized data.
	
	:param: serializedData   The data to add the related resources to.
	:param: key              The key to add to the serialized data.
	:param: relatedResources The related resources to add to the serialized data.
	*/
	private func addToManyRelationship(inout serializedData: [String: AnyObject], key: String, relatedResources: [Resource]?) {
		var linkData: AnyObject
		
		if let resources = relatedResources {
			let IDs: [String] = resources.filter { resource in
				return resource.resourceID != nil
			}.map { resource in
				return resource.resourceID!
			}
			
			linkData = IDs
			
		} else {
			linkData = []
		}
		
		if serializedData["links"] == nil {
			serializedData["links"] = [key: linkData]
		} else {
			var links: [String: AnyObject] = serializedData["links"]! as [String: AnyObject]
			links[key] = linkData
			serializedData["links"] = links
		}
	}
}


// MARK:

class Formatter {

	private func deserialize(value: AnyObject, ofType type: ResourceAttribute.AttributeType) -> AnyObject {
		switch type {
		case .Date:
			return self.deserializeDate(value as String)
		default:
			return value
		}
	}
	
	private func serialize(value: AnyObject, ofType type: ResourceAttribute.AttributeType) -> AnyObject {
		switch type {
		case .Date:
			return self.serializeDate(value as NSDate)
		default:
			return value
		}
	}
	
	// MARK: Date
	
	private lazy var dateFormatter: NSDateFormatter = {
		let formatter = NSDateFormatter()
		formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
		return formatter
	}()

	private func serializeDate(date: NSDate) -> String {
		return self.dateFormatter.stringFromDate(date)
	}

	private func deserializeDate(value: String) -> NSDate {
		if let date = self.dateFormatter.dateFromString(value) {
			return date
		}
		
		return NSDate()
	}
}