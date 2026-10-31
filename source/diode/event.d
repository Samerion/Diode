/// Event handling system.
module diode.event;

@safe:

import diode.set;

/// A subscriber is a function that receives a set of arguments and does not return a value.
///
/// A subscriber can be bound to an [Event] struct, so that it fires whenever the event is
/// triggered.
alias Subscriber(Ts...) = void delegate(Ts) @safe;

/// Defines an event. An event is a collection of delegates that are all whenever the event is
/// triggered.
///
/// The event can provide arguments which are then made available to the delegates.
struct Event(Ts...) {

    private {
        Set!(Subscriber!Ts) _subscribers;
    }

    /// Returns:
    ///     True if the set is empty (has no elements in it).
    bool isEmpty() const {
        return _subscribers.isEmpty();
    }

    /// Returns:
    ///     Number of subscribers bound to the event.
    size_t length() const {
        return _subscribers.length;
    }

    /// Remove all susbcribers from the event.
    void clear() {
        subscribers.clear();
    }

    /// Bind a handler callback to the event. The given function will be called whenever the event
    /// fires.
    ///
    /// The event can have multiple callbacks bound. Each call to `subscribe` will add subscribers
    /// to the list, without removing the previous callbacks.
    ///
    /// Delegates will not be added to the list if they are identical to delegates already in the
    /// set.
    ///
    /// Params:
    ///     subscriber = Callback function to handle the event.
    /// Returns:
    ///     True if the delegate has already been added to the set.
    /// See_Also:
    ///     [unsubscribe]
    bool subscribe(Subscriber!Ts subscriber) {
        return _subscribers.add(subscriber);
    }

    /// ditto
    void opOpAssign(string op : "~")(Subscriber!Ts subscriber) {
        subscribe(subscriber);
    }

    /// Remove a handler callback from the event. Does nothing if the delegate is not in the set.
    /// Params:
    ///     subscriber = Function to remove from the event's subscriber list.
    /// Returns:
    ///     True if the delegate was removed.
    /// See_Also:
    ///     [subscribe]
    bool unsubscribe(Subscriber!Ts subscriber) {
        return _subscribers.remove(subscriber);
    }

    /// Activate the event.
    ///
    /// This will instanteously run each of the callbacks bound to the event with the given
    /// arguments.
    ///
    /// Params:
    ///     arguments = Arguments to pass to the functions.
    void opCall(Ts arguments) {
        foreach (subscriber; _subscribers) {
            subscriber(arguments);
        }
    }

}

@("Event.opCall fires all subscribers")
unittest {
    int total = 1;

    Event!() event;
    event.subscribe({ total *= 3; });
    event.subscribe({ total *= 5; });
    event.subscribe({ total *= 7; });
    assert(total == 1);

    event();
    assert(total == 105);
}

@("Subscribers can be removed from Event")
unittest {
    int total;

    auto dg1 = { total += 1; };
    auto dg2 = { total += 2; };
    Event!() event;
    event.subscribe(dg1);
    event.subscribe(dg2);
    assert(total == 0);

    event();
    assert(total == 3);

    event.unsubscribe(dg1);
    event();
    assert(total == 5);

    event.unsubscribe(dg2);
    event();
    assert(total == 5);
}
