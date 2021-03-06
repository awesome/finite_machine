# encoding: utf-8

module FiniteMachine

  # Base class for state machine
  class StateMachine
    include Threadable

    # Initial state, defaults to :none
    attr_threadsafe :initial_state

    # Final state, defaults to :none
    attr_threadsafe :final_state

    # Current state
    attr_threadsafe :state

    # Events DSL
    attr_threadsafe :events

    # The prefix used to name events.
    attr_threadsafe :namespace

    # The events and their transitions.
    attr_threadsafe :transitions

    # The state machine observer
    attr_threadsafe :observer

    # The state machine subscribers
    attr_threadsafe :subscribers

    # The state machine environment
    attr_threadsafe :env

    # Initialize state machine
    #
    # @api private
    def initialize(*args, &block)
      @subscribers = Subscribers.new(self)
      @events      = EventsDSL.new(self)
      @observer    = Observer.new(self)
      @transitions = Hash.new { |hash, name| hash[name] = Hash.new }
      @env         = Environment.new(target: self)

      @dsl = DSL.new self
      @dsl.call(&block) if block_given?
      send(:"#{@dsl.initial_event}") unless @dsl.defer
    end

    def subscribe(*observers)
      @subscribers.subscribe(*observers)
    end

    # TODO:  use trigger to actually fire state machine events!
    # Notify about event
    #
    # @api public
    def notify(event_type, _transition, *data)
      event_class     = Event.const_get(event_type.capitalize.to_s)
      state_or_action = event_class < Event::Anystate ? state : _transition.name
      _event          = event_class.new(state_or_action, _transition, *data)
      subscribers.visit(_event)
    end

    # Get current state
    #
    # @return [String]
    #
    # @api public
    def current
      state
    end

    # Check if current state machtes provided state
    #
    # @param [String, Array[String]] state
    #
    # @return [Boolean]
    #
    # @api public
    def is?(state)
      if state.is_a?(Array)
        state.include? current
      else
        state == current
      end
    end

    # Retrieve all states
    #
    # @return [Array[Symbol]]
    #
    # @api public
    def states
      event_names.map { |event| transitions[event].to_a }.flatten.uniq
    end

    # Retireve all event names
    #
    # @return [Array[Symbol]]
    #
    # @api public
    def event_names
      transitions.keys
    end

    # Checks if event can be triggered
    #
    # @param [String] event
    #
    # @return [Boolean]
    #
    # @api public
    def can?(event)
      transitions[event].key?(current) || transitions[event].key?(ANY_STATE)
    end

    # Checks if event cannot be triggered
    #
    # @param [String] event
    #
    # @return [Boolean]
    #
    # @api public
    def cannot?(event)
      !can?(event)
    end

    # Checks if terminal state has been reached
    #
    # @return [Boolean]
    #
    # @api public
    def finished?
      is?(final_state)
    end

    #
    #
    # @api public
    def errors
    end

    private

    # Check if state is reachable
    #
    # @api private
    def validate_state(_transition)
      current_states = transitions[_transition.name].keys
      if !current_states.include?(state)  && !current_states.include?(ANY_STATE)
        raise TransitionError, "inappropriate current state '#{state}'"
      end
    end

    # Performs transition
    #
    # @api private
    def transition(_transition, *args, &block)
      validate_state(_transition)

      return CANCELLED unless _transition.conditions.all? { |c| c.call(env) }
      return NOTRANSITION if state == _transition.to

      sync_exclusive do
        notify :exitstate, _transition, *args
        notify :enteraction, _transition, *args

        begin
          _transition.call

          notify :transitionstate, _transition, *args
          notify :transitionaction, _transition, *args
        rescue StandardError => e
          raise TransitionError, "#(#{e.class}): #{e.message}\n" +
            "occured at #{e.backtrace.join("\n")}"
        end

        notify :enterstate, _transition, *args
        notify :exitaction, _transition, *args
      end

      SUCCEEDED
    end

  end # StateMachine
end # FiniteMachine
