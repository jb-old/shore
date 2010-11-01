#!/usr/bin/env coffee -c
###
Shore Math Module
http://jeremybanks.github.com/shore/

Copyright Jeremy Banks <jeremy@jeremybanks.com>
Released under the MIT License
### 

# This module exports a single function under the names S and shore, with a
# single submodule defined as .utility and .U. In most cases you will only
# need to call the module function and not use any of the functions it
# contains directly, provided that you also include shore.parser.
# 
# The module is defined piecemeal:
# 
#   1. the object is created as a function that may be used to create shore
#      objects, using shore.parser if available.
#   
#   2. the shore.utility submodule is defined.
#   
#   3. components of the shore module which are not its types are defined
#      as __not_types and then added to the shore object.
#   
#   4. the shore types are defined initially as __types, provider functions
#      are generated and then it's all added to the shore object.
#   
#   5. the canonizations for the types are defined initially by functions
#      in __definers_of_canonizers, which are evaluated and added added to
#      their respective types.

root = this

former_S = root.S
former_shore = root.shore

shore = root.S = root.shore = (args...) ->
	# The shore object is a function which can be called to create shore values.
	# Without shore.parser it will only be able to create numbers and
	# identifiers. If multiple arguments are provided it will return an array
	# of values, so you can do things like [x, y, z] = shore "x", "y", "z".
	
	if args.length is 1
		arg = args[0]
		
		if typeof arg is "number"
			S.number value: arg
		else if typeof arg is "string"
			if /^[a-zA-Z][a-zA-Z0-9]*'*$/.test arg
				S.identifier value: arg
			else
				if shore.parser?
					shore.parser.parse arg
				else
					throw new Error "shore.parser is not available to interpret expression: #{arg}"
		else
			throw new Error "Unable to handle argument of type #{typeof arg}."
	else
		for arg in args
			shore arg

utility = shore.utility = shore.U =
	# The shore.utility module contains functions that are not shore-specific.
	
	uncamel: (string) ->
		# Converts CamelBack string (not just UPPERCASE) to lowercased_underscore.
		# 
		# Returns undefined if string's not in CamelBack.
		
		if (/^[A-Z]/.test string) and (/[a-z]/.test string)
			parts = (for part in string.split /(?=[A-Z0-9]+)/
				if part then part.toLowerCase())
			return parts.join "_"
	
	memoize: (f, hasher, memory) ->
		# Memoizes a function using a specified hash function and memory object.
		# 
		# Hasher defaults to string conversion, memory to a new empty object.
		
		hasher ?= String
		memory ?= {}
		
		memoized = (arguments...) ->
			"The memoized copy of a function."
			
			key = memoized.hasher [this].concat arguments
			
			if key of memory
				memoized.memory[key]
			else
				memoized.memory[key] = f.apply this, arguments...
		
		memoized.memory = memory
		memoized
	
	sss: (s) ->
		# Splits a String on Spaces
		
		s.split " "
	
	make_providers: (module) ->
		# For each CamelName on module defined module.uncameled_name to be
		# module._make_provider module.CamelName.
		
		for old_name of module:
			if new_name = utility.uncamel old_name
				this[new_name] = module._make_provider module[old_name]
	
	extend: (destination, sources...) ->
		# Copies all properties from each source onto destination
		
		for source in sources
			for property of source
				destination[property] = source[property]
	
	is_array: (object) ->
		# Determines if an object is exactly of type Array
		
		typeof object is "object" and object.constructor is Array
	
	is_object: (object) ->
		# Determines if an object is exactly of type Object
		
		typeof object is "object" and object.constructor is Object

__not_types =
	# Merged onto shore first, as they may be required by the defenitions of
	# shore types.
	
	former_S: former_S,
	former_shore: former_shore,
	
	no_conflict: (deep) ->
		# Resets the value of root.S that what it was before shore was imported.
		# If deep is a true value than root.shore is also reset. Returns shore.
		
		root.S = @former_S
		root.shore = @former_shore if deep
		this
	
	_special_identifiers:
		# If an identifier is created with one of these values it is converted
		# into the corresponding string/tex values.
		
		theta: [ "θ", "\\theta" ]
		pi: [ "π", "\\pi" ]
		tau: [ "τ" , "\\tau" ]
		mu: [ "μ", "\\mu" ]
		sin: [ "sin", "\\sin" ]
		cos: [ "cos", "\\cos" ]
		tan: [ "tan", "\\tan" ]
		arcsin: [ "arcsin", "\\arcsin" ]
		arccos: [ "arccos", "\\arccos" ]
		arctan: [ "arctan", "\\arctan" ]
	
	_make_provider: (cls) ->
		"For now just like new, but later will memoize and such."
		(args...) -> new cls args...
	
	_significance: (x) ->
		if x of shore._significances
			@_significances[x]
		else
			x
	
	_signified: (significance, f) ->
		f.significance = (shore._significance significance)
		f
	
	_canonization: (significance, name, f) ->
		(shore._signified significance, f)
	
	_significances:
		minor: 0
		moderate: 1
		major: 2
	
	canonize: (object, arguments...) ->
		# Canonizes an object or recrusively within Arrays and Objects.
		
		if utility.is_array object
			for value in object
				shore.canonize value, arguments...
		else if utility.is_object object
			new = {}
			for key, value of object
				new[key] = shore.canonize value, arguments...
			new
		else
			object.canonize arguments...

utility.extend shore __not_types

__types =
	# The types of the shore module.
	
	Thing: class Thing
		precedence: 0
		
		req_comps: []
		
		constructor: (@comps)
			for name in @req_comps
				if not @hasOwnProperty name
					raise new Error "#{@type} object requires value for #{name}"
		
		eq: (other) ->
			@type is other.type and @_eq other
		
		canonize: (enough, excess) ->
			enough = shore._significance enough
			excess = shore._significance excess
			
			result = this
			
			loop
				next = result.next_canonization()
				if not next.length then break
				[{significance: significance}, value] = next
				
				if excess? and significance >= excess then break
				result = value
				if enough? and significance >= enough then break
			
			result
		
		next_canonization: ->
			for canonization in @get_canonizers()
				value = canonization.apply this
				
				if value and not @eq(value)
					return [canonization, value]
		
		get_canonizers: -> @_get_canonizers() #(utility.nullary_proto_memo "get_canonizers",
			#-> @_get_canonizers())
		
		_get_canonizers: -> []
		
		to_tex: (context) ->
			context ?= 1
			
			if @precedence < context
				"\\left(#{@to_free_tex()}\\right)"
			else
				@to_free_tex()
		
		to_string: (context) ->
			context ?= 0
			if @precedence < context
				"(#{@to_free_string()})"
			else
				@to_free_string()
		
		to_free_string: -> "(shore.#{@type} value)"
		to_free_tex: -> "\\text{(shore.#{@type} value)}"
		to_cs: -> "(shore.#{@type.toLowerCase()} #{@comps})"
		toString: -> @to_cs()
		
	Value: class Value extends Thing
		is_a_value: true
		
		plus: (other) -> shore.sum [this, other]
		minus: (other) -> shore.sum [this, other.neg()]
		times: (other) -> shore.product [this, other]
		over: (other) -> shore.product [this, other.to_the shore (- 1)]
		pos: -> this
		neg: -> (shore (-1)).times(this)
		to_the: (other) -> shore.exponent this, other
		equals: (other) -> shore.equality [this, other]
		integrate: (variable) -> shore.integral this, variable
		differentiate: (variable) -> shore.derivative this, variable
		given: (substitution) -> shore.pending_substitution this, substitution
		plus_minus: (other) -> shore.with_margin_of_error this, other
		
		_then: (other) ->
			if other.is_a_value
				this.times other
			else
				this.given other
	
	Number: class Number extends Value
		precedence: 10
		req_comps: sss "value"
		
		_eq: (other) -> @value is other.value
		neg: -> shore.number (- @value)
		to_free_tex: -> String @value
		to_free_string: -> String @value
	
	Identifier: class Identifier extends Value
		precedence: 10
		
		req_comps: sss "string_value tex_value"
		
		constructor: (comps) ->
			{ tex_value: tex_value, value: value } = comps
			
			if not tex_value?
				if value of shore._special_identifiers
					[value, tex_value] = shore._special_identifiers[value]
				else
					tex_value = value
			
			super { tex_value: text_value, value: value }
		
		_eq: (other) -> @value is other.value
		to_free_tex: -> @tex_value
		to_free_string: -> @string_value
		
		sub: (other) ->
			string = "#{@string_value}_#{other.to_string()}"
			tex = "{#{@tex_value}}_{#{other.to_tex()}}"
			shore.identifier string, tex
	
	CANOperation: class CANOperation extends Value
		# Commutitive, Assocative N-ary Operation
		
		req_comps: sss "operands"
		
		_eq: (other) ->
			if @operands.length isnt other.operands.length
				return false
			
			for i in [0..@operands.length - 1]
				if not (@operands[i].eq other.operands[i])
					return false
			
			true
		
		to_free_tex: ->
			(((operand.to_tex @precedence) for operand in @operands)
			 .join @tex_symbol)
		
		to_free_string: ->
			(((operand.to_string @precedence) for operand in @operands)
			 .join @string_symbol)
		
	Sum: class Sum extends CANOperation
		precedence: 2
		get_nullary: -> shore 0
		
		string_symbol: " + "
		tex_symbol: " + "
		
		to_free_text: -> super().replace /\+ *\-/, "-" # HACK
		to_free_tex: -> super().replace /\+ *\-/, "-" # HACK
	
	Product: class Product extends CANOperation
		precedence: 4
		get_nullary: -> shore 1
		
		string_symbol: " * "
		tex_symbol: " \\cdot "
		
		_to_free_tex: (operands) ->
			"Without checking for negative powers."
			
			if operands.length > 1 and
			   operands[0].type is "Number" and
				 operands[1].type isnt "Number"
				
				(if operands[0].value isnt -1 then operands[0].to_tex @precedence else "-") +
				(((operand.to_tex @precedence) for operand in operands.slice 1)
				 .join @tex_symbol)
			else
				(((operand.to_tex @precedence) for operand in operands)
				 .join @tex_symbol)
		
		to_free_tex: ->
			positive_exponents = []
			negative_exponents = []
			
			for term in @operands
				if term.type is "Exponent"
					exponent = term.exponent
					
					if exponent.type is "Number" and exponent.value < 0
						negative_exponents.push shore.exponent term.base, exponent.neg()
					else
						positive_exponents.push term
				else
					positive_exponents.push term
			
			positive_exponents or= [shore 1]
			
			top = @_to_free_tex positive_exponents
			
			if negative_exponents.length
				bottom = @_to_free_tex negative_exponents
				"\\tfrac{#{top}}{#{bottom}}"
			else
				top
		
		# to_free_string?
	
	Exponent: class Exponent extends Value
		precedence: 5
		
		constructor: (@base, @exponent) ->
		
		_eq: (other) -> @base.eq(other.base) and @exponent.eq(other.exponent)
		
		to_free_tex: ->
			if @exponent.type is "Number" and @exponent.value is 1
				@base.to_tex @precedence
			else
				"{#{@base.to_tex @precedence}}^{#{@exponent.to_tex()}}"
		
		to_free_string: ->
			if @exponent.type is "Number" and @exponent.value is 1
				@base.to_tex @precedence
			else
				"#{@base.to_string @precedence}^#{@exponent.to_string()}"
		
	Integral: class Integral extends Value
		precedence: 3
		
		constructor: (@expression, @variable) ->
		
		_eq: (other) ->
			@expression.eq(other.expression) and @variable.eq(other.variable)
		
		to_free_tex: ->
			"\\int\\left[#{@expression.to_tex()}\\right]d#{@variable.to_tex()}"
		
		to_free_string: ->
			"int{[#{@expression.to_tex()}]d#{@variable.to_tex()}}"
	
	Derivative: class Derivative extends Value
		precedence: 3
		
		constructor: (@expression, @variable) ->
		
		_eq: (other) ->
			@expression.eq(other.expression) and @variable.eq(other.variable)
		
		to_free_tex: ->
			"\\tfrac{d}{d#{@variable.to_tex()}}\\left[#{@expression.to_tex()}\\right]"
		
		to_free_string: ->
			"d/d#{@variable.to_tex()}[#{@expression.to_tex()}]"
	
	WithMarginOfError: class WithMarginOfError extends Value
		precedence: 1.5
		
		constructor: (@value, @margin) ->
		
		tex_symbol: " \\pm "
		string_symbol: " ± "
		
		to_free_string: ->
			if not @margin.eq (shore 0)
				"#{@value.to_string @precedence} #{@string_symbol} #{@margin.to_string @precedence}"
			else
				@value.to_string @precedence
		
		to_free_tex: ->
			if not @margin.eq (shore 0)
				"#{@value.to_tex @precedence} #{@tex_symbol} #{@margin.to_tex @precedence}"
			else
				@value.to_tex @precedence
	
	Equality: class Equality extends CANOperation
		precedence: 1
		
		is_a_value: false # ><
		
		string_symbol: " = "
		tex_symbol: " = "
	
	PendingSubstitution: class PendingSubstitution extends Value
		precedence: 2.5
		
		thing: "PendingSubstitution"
		
		constructor: (@expression, @substitution) ->
			@is_a_value = @expression.is_a_value
		
		_eq: (other) ->
			@expression.eq(other.expression) and @substitution.eq(other.substitution)
		
		string_symbol: ""
		tex_symbol: ""
		
		to_free_string: ->
			(@expression.to_string @precedence) + @string_symbol + (@substitution.to_string @precedence)
		to_free_tex: ->
			(@expression.to_tex @precedence) + @tex_symbol + (@substitution.to_tex @precedence)

# Set the .type property of each type to itself
for type of __types
	type.type = type

utility.make_providers __types
utility.extend shore __types

__definers_of_canonizers =
	"Thing", -> 
		for significance of shore.significances
			canonization significance, "components #{significance}", ->
				@provider shore.canonize @comps, significance, significance
	
	"CANOperation", -> @__super__.canonizers.concat [
		canonization "minor", "single argument", ->
			@operands[0] if @operands.length is 1
		
		canonization "minor", "no arguments", ->
			@get_nullary() if @operands.length is 0 and @get_nullary
	]
	
	"Sum", -> @__super__.canonizers.concat [
		canonization "major", "numbers in sum", ->
			numbers = []
			not_numbers = []
			
			for operand in @operands
				if operand.type is "Number"
					numbers.push operand
				else
					not_numbers.push operand
			
			if numbers.length > 1
				sum = @get_nullary().value
				
				while numbers.length
					sum += numbers.pop().value
				
				shore.sum [ shore.number sum ].concat not_numbers
	]

for [name, definer] in __definers_of_canonizers
	shore[name].canonizers = definer.apply shore[name]

