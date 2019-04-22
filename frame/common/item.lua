﻿--------------------------------------------------------------------------------
--
--  This file is part of the Doxyrest toolkit.
--
--  Doxyrest is distributed under the MIT license.
--  For details see accompanying license.txt file,
--  the public copy of which is also available at:
--  http://tibbo.com/downloads/archive/doxyrest/license.txt
--
--------------------------------------------------------------------------------

g_itemCidMap = {}
g_itemFileNameMap = {}

function ensureUniqueItemName(item, name, map, sep)
	local mapValue = map[name]

	if mapValue == nil then
		mapValue = {}
		mapValue.itemMap = {}
		mapValue.itemMap[item.id] = 1
		mapValue.count = 1
		map[name] = mapValue
	else
		local index = mapValue.itemMap[item.id]

		if index == nil then
			index = mapValue.count + 1
			mapValue.itemMap[item.id] = index
			mapValue.count = mapValue.count + 1
		end

		if index ~= 1 then
			name = name .. sep .. index

			if map[name] then
				-- solution - try some other separator on collision; but when a proper naming convention is followed, this should never happen.
				error("name collision at: " .. name)
			end
		end
	end

	return name
end

function getItemImportArray(item)
	if item.importArray and next(item.importArray) ~= nil then
		return item.importArray
	end

	local text = getItemInternalDocumentation(item)
	local importArray = {}
	local i = 1
	for import in string.gmatch(text, ":import:([^:]+)") do
		importArray[i] = import
		i = i + 1
	end

	return importArray
end

function getItemImportString(item, indent)
	local importArray = getItemImportArray(item)
	if next(importArray) == nil then
		return ""
	end

	if not indent then
		indent = "\t"
	end

	local importPrefix
	local importSuffix

	if string.match(LANGUAGE, "^c[px+]*$") or LANGUAGE == "idl" then
		importPrefix = "#include <"
		importSuffix = ">\n" .. indent
	elseif string.match(LANGUAGE, "^ja?ncy?$") then
		importPrefix = "import \""
		importSuffix = "\"\n" .. indent
	else
		importPrefix = "import "
		importSuffix = "\n" .. indent
	end

	local s = ""

	for i = 1, #importArray do
		local import = importArray[i]
		s = s .. importPrefix .. import .. importSuffix
	end

	return s
end

function getItemFileName(item, suffix)
	local s

	if item.compoundKind then
		s = item.compoundKind .. "_"
	elseif item.memberKind then
		s = item.memberKind .. "_"
	else
		s = "undef_"
	end

	if item.compoundKind == "group" then
		s = s .. item.name
	else
		local path = string.gsub(item.path, "/operator[%s%p]+$", "/operator")
		s = s .. string.gsub(path, "/", "_")
	end

	s = ensureUniqueItemName(item, s, g_itemFileNameMap, "-")

	if not suffix then
		suffix = ".rst"
	end

	s = s .. suffix

	return s
end

function getItemCid(item)
	local s

	if item.compoundKind == "group" then
		s = item.name
	else
		s = string.gsub(item.path, "/operator[%s%p]+$", "/operator")
		s = string.gsub(s, "@[0-9]+/", "")
		s = string.gsub(s, "/", ".")
	end

	s = string.lower(s)
	s = ensureUniqueItemName(item, s, g_itemCidMap, "-")

	return s
end

function getItemRefTargetString(item)
	local s =
		".. index:: pair: " .. item.memberKind .. "; " .. item.name .. "\n" ..
		".. _cid-" .. getItemCid(item) .. ":\n" ..
		".. _doxid-" .. item.id .. ":\n"

	if item.isSubGroupHead then
		for j = 1, #item.subGroupSlaveArray do
			slaveItem = item.subGroupSlaveArray[j]

			s = s ..
				".. _cid-" .. getItemCid(slaveItem) .. ":\n" ..
				".. _doxid-" .. slaveItem.id .. ":\n"
		end
	end

	return s
end

function getItemArrayOverviewRefTargetString(itemArray)
	local s = ""

	for i = 1, #itemArray do
		local item = itemArray[i]
		if not hasItemRefTarget(item) then
			s = s .. getItemRefTargetString(item)
		end
	end

	return  s
end

function hasItemRefTarget(item)
	return item.hasDocumentation or item.subGroupHead
end

function isTocTreeItem(compound, item)
	return not item.groupId or item.groupId == compound.id
end

function getItemInternalDocumentation(item)
	local s = ""

	for i = 1, #item.detailedDescription.docBlockList do
		local block = item.detailedDescription.docBlockList[i]
		if block.blockKind == "internal" then
			s = s .. block.text .. getSimpleDocBlockListContents(block.childBlockList)
		end
	end

	return s
end

function getItemBriefDocumentation(item, detailsRefPrefix)
	local s = getDocBlockListContents(item.briefDescription.docBlockList)

	if string.len(s) == 0 then
		s = getDocBlockListContents(item.detailedDescription.docBlockList)
		if string.len(s) == 0 then
			return ""
		end

		-- generate brief description from first sentence only
		-- matching space is to handle qualified identifiers(e.g. io.File.open)

		local i = string.find(s, "%.%s", 1)
		if i then
			s = string.sub(s, 1, i)
		end

		s = trimTrailingWhitespace(s)
	end

	if detailsRefPrefix then
		s = s .. " :ref:`More...<" .. detailsRefPrefix .. "doxid-" .. item.id .. ">`"
	end

	return s
end

function getItemDetailedDocumentation(item)
	local brief = getDocBlockListContents(item.briefDescription.docBlockList)
	local detailed = getDocBlockListContents(item.detailedDescription.docBlockList)

	if string.len(detailed) == 0 then
		return brief
	elseif string.len(brief) == 0 then
		return detailed
	else
		return brief .. "\n\n" .. detailed
	end
end

function prepareItemDocumentation(item, compound)
	local hasBriefDocuemtnation = not isDocumentationEmpty(item.briefDescription)
	local hasDetailedDocuemtnation = not isDocumentationEmpty(item.detailedDescription)

	item.hasDocumentation = hasBriefDocuemtnation or hasDetailedDocuemtnation
	if not item.hasDocumentation then
		return false
	end

	if hasDetailedDocuemtnation then
		local text = getItemInternalDocumentation(item)

		item.isSubGroupHead = string.match(text, ":subgroup:") ~= nil
		if item.isSubGroupHead then
			item.subGroupSlaveArray = {}
		end
	end

	return not compound or not item.groupId or item.groupId == compound.id
end

function prepareItemArrayDocumentation(itemArray, compound)

	local hasDocumentation = false
	local subGroupHead = nil

	for i = 1, #itemArray do
		local item = itemArray[i]

		local result = prepareItemDocumentation(item, compound)
		if result then
			hasDocumentation = true
			if item.isSubGroupHead then
				subGroupHead = item
			else
				subGroupHead = nil
			end
		elseif subGroupHead then
			table.insert(subGroupHead.subGroupSlaveArray, item)
			item.subGroupHead = subGroupHead
		end
	end

	return hasDocumentation
end

function isItemInCompoundDetails(item, compound)
	if not item.hasDocumentation then
		return false
	end

	return not item.groupId or item.groupId == compound.id
end

function cmpIds(i1, i2)
	return i1.id < i2.id
end

function cmpNames(i1, i2)
	return i1.name < i2.name
end

function cmpTitles(i1, i2)
	return i1.title < i2.title
end

-------------------------------------------------------------------------------
