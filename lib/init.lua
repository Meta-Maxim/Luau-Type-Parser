--[[
MIT License

Copyright ©️ 2022 Maxim Borsch <@Meta_Maxim>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]

local Types = require(script.Parent.LuauTypes)

export type ParserOptions = {
	CustomLiteralParsers: { (string) -> Types.Type? }?,
}

export type Parser = {
	typeStack: {},
	currentNode: Types.Type,
	closedUnions: { [Types.Union]: boolean },
	closedTables: { [Types.Table]: boolean },
	wrappedTuples: { [Types.Tuple]: boolean },
	keyBuffer: { string },
	popStack: () -> Types.Type,
	addToStack: (Types.Type) -> nil,
	getKey: () -> string,
	isTuplePossible: () -> boolean,
	isTableClosed: () -> boolean,
	isUnionClosed: () -> boolean,
	isTupleWrapped: () -> boolean,
	markTableClosed: () -> nil,
	markUnionClosed: () -> nil,
	markTupleWrapped: () -> nil,
	parseLiteral: (string?) -> Types.Type,
	parseTableBegin: () -> nil,
	parseTableEnd: () -> nil,
	parseIndexBegin: () -> nil,
	parseIndexEnd: () -> nil,
	parseField: () -> nil,
	parseUnionBegin: () -> nil,
	parseUnion: () -> nil,
	parseUnionEnd: () -> nil,
	parseOptional: () -> nil,
	parseSeparator: () -> nil,
	Parse: (Parser, string) -> Types.Type,
}

local Parser = {}
Parser.__index = Parser

function Parser.new(parserOptions: ParserOptions?): Parser
	return setmetatable({
		typeStack = {},
		currentNode = nil,
		closedUnions = {},
		closedTables = {},
		wrappedTuples = {},
		keyBuffer = {},
		options = parserOptions or {},
	}, Parser) :: Parser
end

function Parser:Parse(typeDefinition: string): Types.Type
	self.currentNode = nil
	table.clear(self.typeStack)
	table.clear(self.closedUnions)
	table.clear(self.closedTables)
	table.clear(self.wrappedTuples)
	table.clear(self.keyBuffer)

	local literal = self:parseLiteral(typeDefinition)
	if literal then
		return literal
	end

	for i = 1, string.len(typeDefinition) do
		local char = string.sub(typeDefinition, i, i)
		if char == "{" then
			self:parseTableBegin()
		elseif char == "}" then
			self:parseTableEnd()
		elseif char == "[" then
			self:parseIndexBegin()
		elseif char == "]" then
			self:parseIndexEnd()
		elseif char == ":" then
			self:parseField()
		elseif char == "(" then
			self:parseUnionBegin()
		elseif char == "|" then
			self:parseUnion()
		elseif char == ")" then
			self:parseUnionEnd()
		elseif char == "?" then
			self:parseOptional()
		elseif char == "," or char == ";" then
			self:parseSeparator()
		elseif string.find(char, "%w", 1, false) then
			self.keyBuffer[#self.keyBuffer + 1] = char
		end
	end

	if #self.keyBuffer > 0 then
		local keyType = self:parseLiteral()
		local currentNode = self.currentNode
		if currentNode then
			if currentNode.Type == "Tuple" then
				currentNode:AddValueType(keyType)
			elseif currentNode.Type == "Field" then
				if not currentNode.ValueType then
					currentNode.ValueType = keyType
				end
			elseif currentNode.Type == "Map" then
				currentNode.ValueType = keyType
			elseif currentNode.Type == "Union" then
				currentNode:AddType(keyType)
			end
		else
			return keyType
		end
	end

	return self.typeStack[1]
end

function Parser:popStack()
	local typeStack = self.typeStack
	local i = #typeStack
	local node = typeStack[i]
	typeStack[i] = nil
	self.currentNode = typeStack[i - 1]
	return node
end

function Parser:addToStack(node: Types.Type)
	self.typeStack[#self.typeStack + 1] = node
	self.currentNode = node
end

function Parser:getKey(): string
	local keyStr = table.concat(self.keyBuffer)
	table.clear(self.keyBuffer)
	return keyStr
end

function Parser:isTuplePossible(): boolean
	for i, t in ipairs(self.typeStack) do
		if i == #self.typeStack and t.Type ~= "Tuple" then
			continue
		end
		if not (t.Type == "Union" or t.Type == "Optional") then
			return false
		end
	end
	return true
end

function Parser:isTableClosed(): boolean
	return self.closedTables[self.currentNode] ~= nil
end

function Parser:isUnionClosed(): boolean
	return self.closedUnions[self.currentNode] ~= nil
end

function Parser:isTupleWrapped(): boolean
	return self.wrappedTuples[self.currentNode] ~= nil
end

function Parser:markTableClosed()
	self.closedTables[self.currentNode] = true
end

function Parser:markUnionClosed()
	self.closedUnions[self.currentNode] = true
end

function Parser:markTupleWrapped()
	self.wrappedTuples[self.currentNode] = true
end

function Parser:parseLiteral(literal: string?): Types.Type
	if not literal then
		literal = self:getKey()
	end

	if Types.Literals[literal] then
		return Types.Literals[literal]
	end

	if self.options.CustomLiteralParsers then
		for _, parser in ipairs(self.options.CustomLiteralParsers) do
			local customLiteral: Types.Type? = parser(literal)
			if customLiteral then
				return customLiteral
			end
		end
	end
end

function Parser:parseTableBegin()
	local currentNode = self.currentNode
	if currentNode then
		if currentNode.Type == "table" then
			local newTable = Types.Table.new()
			local newMapType = Types.Map.new(Types.Number, newTable)
			currentNode:AddMapType(newMapType)
			self:addToStack(newTable)
		elseif currentNode.Type == "Tuple" then
			local newTable = Types.Table.new()
			currentNode:AddValueType(newTable)
			self:addToStack(newTable)
		elseif currentNode.Type == "Map" or currentNode.Type == "Field" then
			local newTable = Types.Table.new()
			currentNode.ValueType = newTable
			self:addToStack(newTable)
		elseif currentNode.Type == "Union" then
			local newTable = Types.Table.new()
			currentNode:AddType(newTable)
			self:addToStack(newTable)
		end
	else
		self:addToStack(Types.Table.new())
	end
end

function Parser:parseTableEnd()
	local currentNode = self.currentNode
	if currentNode.Type == "table" then
		if self:isTableClosed() then
			self:popStack()
		end
	end
	currentNode = self.currentNode
	if currentNode.Type == "table" then
		self:markTableClosed()
		if #self.keyBuffer > 0 then
			local newMapType = Types.Map.new(Types.Number, self:parseLiteral())
			currentNode:AddMapType(newMapType)
		end
	elseif currentNode.Type == "Map" or currentNode.Type == "Field" then
		if #self.keyBuffer > 0 then
			currentNode.ValueType = self:parseLiteral()
		end
		self:popStack()
		self:markTableClosed()
	elseif currentNode.Type == "Union" then
		if #self.keyBuffer > 0 then
			currentNode:AddType(self:parseLiteral())
		end
		while self.currentNode.Type ~= "table" do
			self:popStack()
		end
		self:markTableClosed()
	elseif currentNode.Type == "Optional" then
		while self.currentNode.Type ~= "table" do
			self:popStack()
		end
		self:markTableClosed()
	end
end

function Parser:parseIndexBegin()
	local currentNode = self.currentNode
	if currentNode.Type == "table" then
		local newMapType = Types.Map.new()
		currentNode:AddMapType(newMapType)
		self:addToStack(newMapType)
	end
end

function Parser:parseIndexEnd()
	local currentNode = self.currentNode
	if currentNode.Type == "Map" then
		currentNode.KeyType = self:parseLiteral()
	else
		if currentNode.Type == "Union" then
			if #self.keyBuffer > 0 then
				currentNode:AddType(self:parseLiteral())
			end
		end
		while self.currentNode.Type ~= "Map" do
			self:popStack()
		end
	end
end

function Parser:parseUnionBegin()
	local union = Types.Union.new()
	local currentNode = self.currentNode
	if currentNode then
		if currentNode.Type == "Union" and not self:isUnionClosed() then
			currentNode:AddType(union)
		elseif currentNode.Type == "Field" or currentNode.Type == "Map" then
			if currentNode.Type == "Field" then
				currentNode.ValueType = union
			elseif currentNode.Type == "Map" then
				if not currentNode.KeyType then
					currentNode.KeyType = union
				else
					currentNode.ValueType = union
				end
			end
		elseif currentNode.Type == "Tuple" then
			currentNode:AddValueType(union)
		elseif currentNode.Type == "table" then
			local newMapType = Types.Map.new(Types.Number, union)
			currentNode:AddMapType(newMapType)
			self:addToStack(newMapType)
		end
	end
	self:addToStack(union)
	self:markTupleWrapped()
end

function Parser:parseUnion()
	local currentNode = self.currentNode
	if currentNode then
		if currentNode.Type == "Union" then
			if #self.keyBuffer > 0 then
				currentNode:AddType(self:parseLiteral())
			else
				local union = Types.Union.new()
				union:AddType(currentNode)
				local subUnion = self:popStack()
				currentNode = self.currentNode
				if currentNode then
					if currentNode.Type == "Field" or currentNode.Type == "Map" then
						currentNode.ValueType = union
					elseif currentNode.Type == "Tuple" then
						currentNode:ReplaceValueType(subUnion, union)
					elseif currentNode.Type == "Union" then
						currentNode:ReplaceType(subUnion, union)
					end
				end
				self:addToStack(union)
			end
		elseif currentNode.Type == "Field" or currentNode.Type == "Map" then
			local union = Types.Union.new()
			union:AddType(self:parseLiteral())
			if currentNode.Type == "Field" then
				currentNode.ValueType = union
			elseif currentNode.Type == "Map" then
				if not currentNode.KeyType then
					currentNode.KeyType = union
				else
					currentNode.ValueType = union
				end
			end
			self:addToStack(union)
		elseif currentNode.Type == "Tuple" then
			local union = Types.Union.new()
			if #self.keyBuffer == 0 then -- if tuple is closed
				local tuple = self:popStack()
				union:AddType(tuple)
				currentNode = self.currentNode
				if currentNode then
					currentNode:ReplaceType(tuple, union)
				end
			else
				union:AddType(self:parseLiteral())
				currentNode:AddValueType(union)
			end
			self:addToStack(union)
		elseif currentNode.Type == "table" then
			local union = Types.Union.new()
			if self:isTableClosed() then
				local tbl = self:popStack()
				union:AddType(tbl)
				currentNode = self.currentNode
				if currentNode then
					if currentNode.Type == "Field" or currentNode.Type == "Map" then
						currentNode.ValueType = union
					elseif currentNode.Type == "Tuple" then
						currentNode:ReplaceValueType(tbl, union)
					elseif currentNode.Type == "Union" then
						currentNode:ReplaceType(tbl, union)
					end
				end
			else
				if #self.keyBuffer > 0 then
					union:AddType(self:parseLiteral())
				end
				local newMapType = Types.Map.new()
				newMapType.KeyType = Types.Number
				newMapType.ValueType = union
				currentNode:AddMapType(newMapType)
				self:addToStack(newMapType)
			end
			self:addToStack(union)
		elseif currentNode.Type == "Optional" then
			local optional = self:popStack()
			local union = Types.Union.new()
			union:AddType(optional)
			currentNode = self.currentNode
			if currentNode then
				if currentNode.Type == "Field" or currentNode.Type == "Map" then
					currentNode.ValueType = union
				elseif currentNode.Type == "Tuple" then
					currentNode:ReplaceValueType(optional, union)
				elseif currentNode.Type == "Union" then
					currentNode:ReplaceType(optional, union)
				end
			end
			self:addToStack(union)
		end
	else
		local union = Types.Union.new()
		union:AddType(self:parseLiteral())
		self:addToStack(union)
	end
end

function Parser:parseUnionEnd()
	local currentNode = self.currentNode
	while
		#self.typeStack > 1
		and ((currentNode.Type == "Union" and self:isUnionClosed()) or currentNode.Type == "Optional")
	do
		self:popStack()
		currentNode = self.currentNode
	end
	if currentNode.Type == "Union" then
		if #self.keyBuffer > 0 then
			currentNode:AddType(self:parseLiteral())
		end
		self:markUnionClosed()
		if not self:isTupleWrapped() then
			self:popStack()
			self:markUnionClosed()
		end
	elseif currentNode.Type == "Tuple" then
		if #self.keyBuffer > 0 then
			currentNode:AddValueType(self:parseLiteral())
		end
	else
		self:popStack()
		self:markUnionClosed()
	end
end

function Parser:parseField()
	local currentNode = self.currentNode
	if currentNode then
		if currentNode.Type == "table" then
			local keyStr = self:getKey()
			local newFieldType = Types.Field.new(keyStr)
			currentNode:AddFieldType(newFieldType)
			self:addToStack(newFieldType)
		end
	end
end

function Parser:parseOptional()
	if #self.keyBuffer > 0 then
		local value = self:parseLiteral()
		local optional = Types.Optional.new(value)
		local currentNode = self.currentNode
		if currentNode then
			if currentNode.Type == "Field" or currentNode.Type == "Map" then
				currentNode.ValueType = optional
			elseif currentNode.Type == "Tuple" then
				currentNode:AddValueType(optional)
			elseif currentNode.Type == "Union" then
				currentNode:AddType(optional)
			end
		end
		self:addToStack(optional)
	else
		local currentNode = self.currentNode
		assert(currentNode ~= nil, "Missing value before optional operator.")
		if currentNode.Type == "table" then
			assert(self:isTableClosed(), "Missing value before optional operator, got an incomplete table instead.")
		end
		local value = self:popStack()
		local optional = Types.Optional.new(value)
		currentNode = self.currentNode
		if currentNode then
			if currentNode.Type == "Field" or currentNode.Type == "Map" then
				currentNode.ValueType = optional
			elseif currentNode.Type == "Tuple" then
				currentNode:ReplaceValueType(value, optional)
			elseif currentNode.Type == "Union" then
				currentNode:ReplaceType(value, optional)
			end
		end
		self:addToStack(optional)
	end
end

function Parser:parseSeparator()
	local currentNode = self.currentNode
	if currentNode then
		if currentNode.Type == "Tuple" then
			local newType = self:parseLiteral()
			currentNode:AddValueType(newType)
		elseif currentNode.Type == "table" then
			if self:isTableClosed() then
				if self:isTuplePossible() then
					local t = self:popStack()
					local tuple = Types.Tuple.new()
					tuple:AddValueType(t)
					self:addToStack(tuple)
				else
					self:popStack()
					currentNode = self.currentNode
					if currentNode.Type == "Map" or currentNode.Type == "Field" then
						self:popStack()
					end
				end
			end
		elseif currentNode.Type == "Map" or currentNode.Type == "Field" then
			if not currentNode.ValueType then
				currentNode.ValueType = self:parseLiteral()
			end
			self:popStack()
		elseif currentNode.Type == "Optional" and #self.typeStack == 1 then
			local tuple = Types.Tuple.new()
			tuple:AddValueType(self:popStack())
			self:addToStack(tuple)
		elseif currentNode.Type == "Union" or currentNode.Type == "Optional" then
			while
				#self.typeStack > 1
				and (
					(currentNode.Type == "Union" and self:isUnionClosed())
					or currentNode.Type == "Map"
					or currentNode.Type == "Field"
					or currentNode.Type == "Optional"
				)
			do
				self:popStack()
				currentNode = self.currentNode
			end
			if currentNode.Type == "Union" then
				if self:isTupleWrapped() then
					if #self.keyBuffer > 0 then
						currentNode:AddType(self:parseLiteral())
					end
					if self:isTuplePossible() then
						local tuple = Types.Tuple.new()
						local union = self:popStack()
						tuple:AddValueType(union.Types[1])
						currentNode = self.currentNode
						if currentNode then
							if currentNode.Type == "Union" then
								currentNode:ReplaceType(union, tuple)
							elseif currentNode.Type == "Map" or currentNode.Type == "Field" then
								currentNode.ValueType = tuple
							end
						end
						self:addToStack(tuple)
					end
				else -- if not self:isTupleWrapped()
					self:markUnionClosed()
					if #currentNode.Types > 0 then
						if #self.keyBuffer > 0 then
							currentNode:AddType(self:parseLiteral())
						end
						self:popStack()
						if self:isTuplePossible() then
							local tuple = Types.Tuple.new()
							local union = self:popStack()
							if #self.typeStack == 0 then
								tuple:AddValueType(union.Types[1])
							else
								tuple:AddValueType(union)
							end
							currentNode = self.currentNode
							if currentNode then
								if currentNode.Type == "Union" then
									currentNode:AddType(tuple)
								elseif currentNode.Type == "Map" or currentNode.Type == "Field" then
									currentNode.ValueType = tuple
								end
							end
							self:addToStack(tuple)
						end
					else -- if is empty union becoming tuple
						if self:isTuplePossible() then
							local union = self:popStack()
							local tuple = Types.Tuple.new()
							if #self.keyBuffer > 0 then
								tuple:AddValueType(self:parseLiteral())
							end
							currentNode = self.currentNode
							if currentNode then
								if currentNode.Type == "Union" then
									currentNode:ReplaceType(union, tuple)
								elseif currentNode.Type == "Map" or currentNode.Type == "Field" then
									currentNode.ValueType = tuple
								end
							end
							self:addToStack(tuple)
						end
					end
				end
			end
		end
	else
		local tuple = Types.Tuple.new()
		tuple:AddValueType(self:parseLiteral())
		self:addToStack(tuple)
	end
end

return Parser
