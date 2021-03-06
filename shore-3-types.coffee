sss = utility.sss

__types =
	# The types of the shore module.
	
	Thing: class Thing
		# The underlying mechanisms of all of our types, without anything of
		# actual math.
		
		is_shore_thing: true
		
		req_comps: []
		
		identifier_string_set: utility.memoize ->
			all = {}
			
			if @type is shore.Identifier
				all[@comps.value] = true
			
			shore.utility.call_in @comps, (o) -> utility.extend all, o.identifier_string_set() if o.is_shore_thing
			
			all
		
		subbable_id_set: utility.memoize (strict) ->
			strict ?= true
			
			all = {}
			
			if @type is shore.Identifier
				all[@comps.value] = true
			
			shore.utility.call_in @comps, (o) -> utility.extend all, (o.subbable_id_set strict) if o.is_shore_thing
			
			all
	
		uses_identifier: (o) ->
			o.comps.value of @identifier_string_set()
		
		constructor: (@comps) ->
			for name in @req_comps
				if not @comps[name]?
					throw new Error "#{@name ? @constructor} object requires value for #{name}"
		
		is: (other) ->
			@type is other?.type and shore.is @comps, other.comps
		
		isnt: (other) ->
			not @is other
		
		__hash__: ->
			@name + ":" + utility.hash @comps
		
		canonize: utility.memoize (limit, enough) ->
			limit = shore._significance limit
			enough = shore._significance enough
			
			result = this
			loop
				next = result.next_canonization()
				if not next.length then break
				
				[{significance: significance}, value] = next
				
				if limit? and significance > limit then break
				result = value
				if enough? and significance >= enough then break
			
			result
		
		next_canonization: ->
			for canonization in @canonizers
				value = canonization.apply this
				
				if value and not @is(value)
					return [canonization, value]
		
		outer_tightness: 0
		inner_tightness: 0 # TODO
		
		to_tex: (context, args...) ->
			context ?= 1
			
			if @outer_tightness < context
				"\\left(#{@to_free_tex args...}\\right)"
			else
				@to_free_tex args...
		
		to_string: (context, args...) ->
			context ?= 0
			if @outer_tightness < context
				"(#{@to_free_string args...})"
			else
				@to_free_string args...
		
		to_free_string: -> "(shore.#{@type} value)"
		to_free_tex: -> "\\text{(shore.#{@type} value)}"
		to_cs: -> "(shore.#{@name.toLowerCase()} #{@comps})"
		toString: -> @to_cs()
		
		_then: (other) ->
			if other.is_a_value
				this.times other
			else
				this.given other
		
		given: (equation) ->
			if equation not instanceof shore.Equality or
				 equation.comps.values.length isnt 2
				throw new Error "given equation must be two-element Equality."
			[ original, replacement ] = equation.comps.values
			
			shore.pending_substitution
				value: this
				original: original
				replacement: replacement
		
		substitute: (original, replacement, force) ->
			force ?= false
			
			shore.substitute this, original, replacement, force
		
		derivatives: []
		integrals: []
		# overwhelming-significance derivatives and integrals can be hard-coded
		# in an array of [ identifier, result ] arrays. added for use with builtin
		# external functions.
		
		
	Value: class Value extends Thing
		known_constant: false
		is_a_value: true
		
		plus: (other) -> shore.sum operands: [this, other]
		minus: (other) -> shore.sum operands: [this, other.neg()]
		times: (other) -> shore.product operands: [this, other]
		over: (other) -> shore.product operands: [this, other.to_the shore (- 1)]
		pos: -> this
		neg: -> (shore (-1)).times(this)
		to_the: (other) -> shore.exponent base: this, exponent: other
		equals: (other) -> shore.equality values: [this, other]
		integrate: (variable) -> shore.integral expression: this, variable: variable
		differentiate: (variable) -> shore.derivative expression: this, variable: variable
		plus_minus: (other) -> shore.with_margin_of_error value: this, margin: other
	
	Number: class Number extends Value
		known_constant: true
		outer_tightness: 10
		req_comps: sss "value"
		
		neg: -> shore.number value: -@comps.value
		
		to_free_tex: ->
			if @comps.id?
				@comps.id.to_free_tex arguments...
			else
				String 1 * @comps.value.toFixed(8) # go to hell
		
		to_free_string: ->
			if @comps.id?
				@comps.id.to_free_string arguments...
			else
				String @comps.value
	
	Identifier: class Identifier extends Value
		outer_tightness: 10
		
		req_comps: sss "value tex_value"
		
		constructor: (comps) ->
			{ tex_value: tex_value, value: value } = comps
			
			if not tex_value?
				if value of shore._special_identifiers
					[value, tex_value] = shore._special_identifiers[value]
				else
					tex_value = value
			
			super { tex_value: tex_value, value: value }
		
		to_free_tex: -> @comps.tex_value
		to_free_string: -> @comps.value
		
		_substitute: (original, replacement, strict) ->
			if @is original
				replacement
			else
				if strict
					@given original.equals replacement
				else
					this
		
		sub: (other) ->
			string = "#{@comps.value}_#{other.to_string()}"
			tex = "{#{@comps.tex_value}}_{#{other.to_tex()}}"
			
			shore.identifier value: string, tex_value: tex
	
	CANOperation: class CANOperation extends Value
		# Commutitive, Assocative N-ary Operation
		
		req_comps: sss "operands"
		
		to_free_tex: (symbol) ->
			symbol ?= @tex_symbol
			
			(((operand.to_tex @outer_tightness) for operand in @comps.operands)
			 .join symbol)
		
		to_free_string: (symbol) ->
			symbol ?= @string_symbol
			
			(((operand.to_string @outer_tightness) for operand in @comps.operands)
			 .join symbol)
		
	Sum: class Sum extends CANOperation
		outer_tightness: 2
		get_nullary: -> shore 0
		
		string_symbol: " + "
		tex_symbol: " + "
		
		to_free_string: -> super().replace /\+ *\-/, "-" # HACK
		to_free_tex: -> super().replace /\+ *\-/, "-" # HACK
	
	Product: class Product extends CANOperation
		outer_tightness: 4
		get_nullary: -> shore 1
		
		string_symbol: " * "
		tex_symbol: " \\cdot "
		
		_to_free_tex: (operands) ->
			"Without checking for negative powers."
			
			if operands.length > 1 and
			   operands[0].type is shore.Number and
				 operands[1].type isnt shore.Number
				
				(if operands[0].comps.value isnt -1 then operands[0].to_tex @outer_tightness else "-") +
				(((operand.to_tex @outer_tightness) for operand in operands.slice 1)
				 .join @tex_symbol)
			else
				(((operand.to_tex @outer_tightness) for operand in operands)
				 .join @tex_symbol)
		
		to_free_tex: ->
			positive_exponents = []
			negative_exponents = []
			
			for term in @comps.operands
				if term.type is shore.Exponent
					exponent = term.comps.exponent
					
					if exponent.type is shore.Number and exponent.comps.value < 0
						negative_exponents.push shore.exponent base: term.comps.base, exponent: exponent.neg()
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
		
		to_free_string: ->
			(operand.to_string(20) for operand in @comps.operands).join ""
	
	Exponent: class Exponent extends Value
		outer_tightness: 5
		req_comps: sss "base exponent"
		
		to_free_tex: ->
			if @comps.exponent.type is shore.Number and @comps.exponent.comps.value is 1
				@comps.base.to_tex @outer_tightness
			else
				"{#{@comps.base.to_tex @outer_tightness}}^{#{@comps.exponent.to_tex()}}"
		
		to_free_string: ->
			if @comps.exponent.type is shore.Number and @comps.exponent.comps.value is 1
				@comps.base.to_string @outer_tightness
			else
				"#{@comps.base.to_string @outer_tightness}^#{@comps.exponent.to_string()}"
	
	IntDerAb: class IntDerAb extends Value
		# stuff shared by Integrals and Derivatives.
		
		outer_tightness: 3
		req_comps: sss "variable expression"
		
		subbable_id_set: ->
			result = @comps.expression.subbable_id_set()
			for key of @comps.variable.subbable_id_set()
				delete result[key]
			result
		
		_substitute: (original, replacement, strict) ->
			strict ?= true
			
			if original.is @comps.variable
				if strict
					this.given original.equals replacement
				else
					this
				# no-op, but save for post-canonization
			else
				@provider
					variable: @comps.variable
					expression: shore.substitute @comps.expression, original, replacement, strict
	
	Integral: class Integral extends IntDerAb
		to_free_tex: ->
			"\\int\\left[#{@comps.expression.to_tex()}\\right]d#{@comps.variable.to_tex()}"
		
		to_free_string: ->
			"int{[#{@comps.expression.to_string()}]d#{@comps.variable.to_string()}}"
	
	Derivative: class Derivative extends IntDerAb
		to_free_tex: ->
			"\\tfrac{d}{d#{@comps.variable.to_tex()}}\\left[#{@comps.expression.to_tex()}\\right]"
		
		to_free_string: ->
			"d/d#{@comps.variable.to_string()}[#{@comps.expression.to_string()}]"
	
	WithMarginOfError: class WithMarginOfError extends Value
		outer_tightness: 1.5
		req_comps: sss "value margin"
		
		tex_symbol: " \\pm "
		string_symbol: " ± "
		
		to_free_string: ->
			if not @margin.is (shore 0)
				"#{@comps.value.to_string @outer_tightness}
				 #{@string_symbol}
				 #{@comps.margin.to_string @outer_tightness}"
			else
				@comps.value.to_string @outer_tightness
		
		to_free_tex: ->
			if not @margin.is (shore 0)
				"#{@comps.value.to_tex @outer_tightness}
				 #{@tex_symbol}
				 #{@comps.margin.to_tex @outer_tightness}"
			else
				@comps.value.to_tex @outer_tightness
	
	Matrix: class Matrix extends Value
		req_comps: sss "values"
		
		to_free_tex: ->
			"\\begin{matrix}
			#{
				((v.to_tex() for v in row).join('&') for row in @comps.values).join(' \\\\\n')
			}
			\\end{matrix}"
	
	Equation: class Equation extends Thing
		outer_tightness: 1
		req_comps: sss "values"
		
		to_free_tex: (symbol) ->
			symbol ?= @tex_symbol
			
			(((value.to_tex @outer_tightness) for value in @comps.values)
			 .join symbol)
		
		to_free_string: (symbol) ->
			symbol ?= @string_symbol
			
			(((value.to_string @outer_tightness) for value in @comps.values)
			 .join symbol)
	
	Equality: class Equality extends Equation
		string_symbol: " = "
		tex_symbol: " = "
		
	ExternalNumericFunction: class ExternalNumericFunction extends Value
		req_comps: sss "identifier arguments f"
		
		specified: ->
			for arg in @comps.arguments
				if arg.type is shore.Identifier
					return false
			true
		
		to_string: ->
			if not @specified()
				@comps.identifier.to_string arguments...
			else
				(@comps.identifier.to_string arguments...) + "_external(#{(shore.to_string a for a in  @comps.arguments).join ', '})"
		
		to_tex: ->
			if not @specified()
				@comps.identifier.to_tex arguments...
			else
				(@comps.identifier.to_tex arguments...) + "_{external}(#{(shore.to_tex a for a in  @comps.arguments).join ', '})"
	
	PendingSubstitution: class PendingSubstitution extends Thing
		outer_tightness: 2.5
		
		req_comps: sss "value original replacement"
		
		identifier_string_set: ->
			# TODO: maybe this should include the replacement?
			@comps.expression.identifier_string_set()
		
		constructor: (comps) ->
			@is_a_value = comps.original.is_a_value
			super comps
		
		string_symbol: " = "
		tex_symbol: " = "
		
		to_free_string: ->
			"#{@comps.value.to_string @outer_tightness}(#{@comps.original.to_string @outer_tightness} #{@string_symbol} #{@comps.replacement.to_string @outer_tightness})"
		
		to_free_tex: ->
			"#{@comps.value.to_tex @outer_tightness}(#{@comps.original.to_tex @outer_tightness} #{@tex_symbol} #{@comps.replacement.to_tex @outer_tightness})"
		
		_substitute: (original, replacement, strict) ->
			if strict
				this.given (original.equals replacement)
			else
				@provider
					value: @comps.value.substitute original, replacement, strict
					original: @comps.original
					replacement: @comps.replacement
		
		subbable_id_set: (strict) ->
			strict ?= true
			
			if strict
				{}
			else
				@comps.value.subbable_id_set()
	
	System: class System extends Thing
		outer_tightness: 1000
		req_comps: sss "equations"
		
		to_free_string: -> (eq.to_string for eq in @comps.equations).join "\n"
		to_free_tex: -> (eq.to_tex 0, "&#{eq.tex_symbol}" for eq in @comps.equations).join " \\\\\n"
		
		tex_the_steps: (interval) ->
			interval ?= "significant"
			
			original = this
			
			lines = []
			
			final = utility.set (eq.to_free_tex " &= " for eq in original.canonize().comps.equations)
			previous = utility.set (eq.to_free_tex " &= " for eq in original.comps.equations)
			
			current = original.canonize null, interval
			
			ls = (s) -> (s.split " &= ")[0]
			
			while current isnt previous_
				for eq_ in current.comps.equations
					eq = eq_.to_free_tex " &= "
					
					if eq not of previous# and eq not of final
						if lines.length and (ls eq) is (ls lines[lines.length - 1])
							eq = eq.replace /^.*? &= /, "&= "
						
						lines.push eq
				
				previous = utility.set (eq.to_free_tex " &= " for eq in current.comps.equations)
				previous_ = current
				current = current.canonize null, interval
			
			lines.join "\\\\\n"

# Set the .type property of each type to itself
for name, type of __types
	type::type = type # TODO: just use .constructor
	type::name = name # TODO: something better

utility.extend shore, __types
utility.make_providers shore

