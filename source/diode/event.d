/// Event handling system.
module diode.event;

@safe:

import std.meta;
import std.traits;
import diode.set;
import diode.object;

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

/// A `Publisher` provides data through a delegate.
interface Publisher(Ts...) : Safe {

    /// Bind a delegate to call when the publisher has data to provide.
    ///
    /// Subscribing via this method may or may not remove previous subscribers from the set;
    /// this behavior is up to the implementation.
    ///
    /// Params:
    ///     subscriber = Delegate to subscribe to the publisher.
    void subscribe(Subscriber!Ts subscriber);

}

/// Returns `true` if given `T` is a `Publisher` interface. Returns `false` for classes.
enum isPublisherInterface(T) = is(T == Publisher!Args, Args...);

/// Provides a tuple of all `Publisher` types implemented by given `T`.
alias PublisherTypes(T) = Filter!(isPublisherInterface, NoDuplicates!(InterfacesTuple!T));

/// Returns a subscriber type equivalent of given publisher type
template SubscriberOf(T)
if (isPublisherInterface!T) {
    static if (is(T == Publisher!Args, Args...)) {
        alias SubscriberOf = Subscriber!Args;
    }
    else static assert(false);
}

/// Create a tuple of publisher types implemented by T, filtered to those accepted by given
/// subscriber.
alias MatchPublisher(alias subscriber, T) = Filter!(
    ApplyLeft!(acceptsPublisherArguments, subscriber),
    PublisherTypes!T);

/// Check if given given delegate accepts types from the given publisher type. The delegate may
/// not necessarily be a valid argument for the publisher; the return value is not checked.
template acceptsPublisherArguments(alias subscriber, T)
if (isPublisherInterface!T) {
    static if (is(T == Publisher!Args, Args...)) {
        enum acceptsPublisherArguments = __traits(compiles, subscriber(Args.init));
    }
    else {
        enum acceptsPublisherArguments = false;
    }
}

/// `then` is a convenience method over `Publisher.subscribe` that can correctly resolve
/// overloading and template methods in cases where the given type implements multiple [Publisher]
/// interfaces. Furthermore, `then` is chainable and will automatically create a `Publisher` type
/// to match the return type of given delegate.
///
/// Params:
///     publisher = Publisher to subscriber to.
///     callback  = Delegate to call when the publisher provides data.
/// Returns:
///     Returns a [Pipe] object that wraps the return value of the publisher provided.
///     This pipe can be subscribed to, so that once `then` receives data, any data provided by
///     the callback's return value can be received through the pipe.
auto then(alias callback, T)(T publisher)
if (PublisherTypes!T.length > 0) {

    // Match against one of the publishers
    alias MatchingPublishers = MatchPublisher!(callback, T);
    static assert(MatchingPublishers.length == 1,
        "delegate passed to `then` matches multiple publishers: " ~ MatchingPublishers.stringof);

    alias MatchingPublisher = MatchingPublishers[0];

    // Get the publisher and its arguments
    static if (is(MatchingPublisher == Publisher!Args, Args...)) {
        auto matchingPublisher = cast(MatchingPublisher) publisher;
        assert(matchingPublisher !is null);

        alias Return = typeof(callback(Args.init));

        // Instantiate and perform the call
        auto dg = delegate (Args args) @safe => callback(args);
        static if (is(Return == void)) {
            matchingPublisher.subscribe(dg);
        }
        else {
            auto pipe = new Pipe!(Return, Args)(dg);
            matchingPublisher.subscribe(&pipe.put);
            return pipe;
        }

    }
    else static assert(false);
}

/// `then` can resolve overloads for subscription
@("`then` can resolve overloads for subscription")
unittest {
    class A : Publisher!int, Publisher!string {
        mixin implementSafe;

        void subscribe(Subscriber!int a) {
            a(1);
        }

        void subscribe(Subscriber!string a) {
            a("A");
        }
    }

    int[] numbers;
    string[] texts;

    auto a = new A;
    // a.subscribe((a) { numbers ~= a; });  // This would fail
    // a.subscribe((a) { texts ~= a; });
    a.then!((a) { numbers ~= a; });
    a.then!((a) { texts ~= a; });
    assert(numbers == [1]);
    assert(texts == ["A"]);
}

@("`then` is chainable")
unittest {
    class YieldThree : Publisher!int {
        mixin implementSafe;
        mixin implementPublisher!int;

        void call() @safe {
            subscriber(3);
        }
    }

    class TimesFive : Publisher!int {
        mixin implementSafe;
        mixin implementPublisher!int;

        int value;

        TimesFive setup(int value) @safe {
            this.value = value;
            return this;
        }

        void call() @safe {
            subscriber(value * 5);
        }
    }

    int result;

    auto yieldThree = new YieldThree;
    auto timesFive = new TimesFive;

    yieldThree
        .then!(a => timesFive.setup(a))
        .then!((a) { result = a; });

    yieldThree.call();
    timesFive.call();
    assert(result == 15);
}

@("`then` supports chaining non-Publisher types")
unittest {
    class A : Publisher!int {
        mixin implementSafe;
        mixin implementPublisher!int;
    }

    auto a = new A;
    int result;

    a
        .then!((a) => a * 7)
        .then!((a) => result = a);
    a.subscriber(5);
    assert(result == 35);
}

/// Construct a [Pipe] object.
/// Params:
///     dg = Delegate to pass to the pipe.
/// Returns:
///     Constructed pipe object.
Pipe!(Return, Args) pipe(Return, Args...)(Return delegate(Args) @safe dg) {
    return new Pipe!(Return, Args)(dg);
}

/// ditto
Pipe!(Return, Args) pipe(Return, Args...)(Return function(Args) @safe dg) {
    return new Pipe!(Return, Args)(delegate(Args args) => dg(args));
}

/// A pipe is a publisher type that calls a delegate and expects a publisher. It will emit
/// data when that publisher provides it with its own.
final class Pipe(Return, Args...) : Safe, PublisherTypes!Return, Publisher!Return {
    mixin implementSafe;

    alias Publishers = PublisherTypes!Return;

    Return delegate(Args) @safe callback;
    staticMap!(SubscriberOf, Publishers) subscribers;
    Subscriber!Return mainSubscriber;

    static foreach (i, T; Publishers) {
        static if (is(T == Publisher!Args2, Args2...)) {
            override mixin implementPipePublisher!(subscribers[i], Args2);
        }
    }
    override mixin implementPipePublisher!(mainSubscriber, Return);

    this(Return delegate(Args) @safe callback) {
        this.callback = callback;
    }

    /// Run the [callback].
    void put(Args args) {
        auto result = callback(args);
        if (mainSubscriber) {
            mainSubscriber(result);
        }
        foreach (i, T; Publishers) {
            auto resultT = cast(T) result;
            assert(resultT !is null);

            auto thisT = cast(T) this;
            assert(thisT !is null);

            static if (is(T == Publisher!Args2, Args2...)) {
                resultT.subscribe(&call!(i, Args2));
            }
            else static assert(false);
        }
    }

    private void call(size_t i, Args...)(Args args) {
        if (subscribers[i]) {
            subscribers[i](args);
        }
    }
}

/// Implement `Publisher`. Accepts only one delegate at a time.
private mixin template implementPipePublisher(alias target, Args...) {
    override void subscribe(Subscriber!Args subscriber) {
        target = subscriber;
    }
}

mixin template implementPublisher(Args...) {
    Subscriber!Args subscriber;

    override void subscribe(Subscriber!Args subscriber) {
        this.subscriber = subscriber;
    }
}
