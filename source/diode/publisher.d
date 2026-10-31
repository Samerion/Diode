/// Provides [Publisher] and chainable [then]: primitives for passing data in asynchronous
/// operations.
module diode.publisher;

@safe:

import std.meta;
import std.traits;
import diode.object;
public import diode.event;

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
///     Returns a [Pipe] object that wraps the return value of the callback provided.
///     This pipe can be subscribed to, so that once `then` receives data, any data provided by
///     the callback's return value can be received through the pipe.
///
///     ---
///     then!(() => /* returns Publisher!T */)  // -> return value is Publisher!T
///     then!(() => /* returns T */)            // -> return value is Publisher!T
///     then!(() => /* returns void */)         // -> return value is Publisher!()
///     ---
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
        auto pipe = new Pipe!(Return, Args)(dg);
        matchingPublisher.subscribe(&pipe.put);
        return pipe;

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

@("`then` supports chaining void")
unittest {
    class Pusher : Publisher!() {
        mixin implementSafe;
        mixin implementPublisher!();
    }

    auto pusher = new Pusher;
    int counter = 1;

    pusher
        .then!({ counter *= 3; })
        .then!({ counter *= 5; })
        .then!({ counter *= 7; });
    pusher.subscriber();
    assert(counter == 105);
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
/// data when that publisher provides it with its own. It can also emit the publisher itself.
///
/// Pipe also supports a special case: `Return == void` in which case it will implement
/// `Publisher!()`, which will fire after the pipe runs the callback.
final class Pipe(Return, Args...) : Safe, PublisherTypes!Return, Publisher!(EraseVoid!Return) {
    mixin implementSafe;

    alias Publishers = PublisherTypes!Return;

    Return delegate(Args) @safe callback;
    staticMap!(SubscriberOf, Publishers) subscribers;
    Subscriber!(EraseVoid!Return) mainSubscriber;

    static foreach (i, T; Publishers) {
        static if (is(T == Publisher!Args2, Args2...)) {
            override mixin implementPipePublisher!(subscribers[i], Args2);
        }
    }
    override mixin implementPipePublisher!(mainSubscriber, EraseVoid!Return);

    this(Return delegate(Args) @safe callback) {
        this.callback = callback;
    }

    /// Run the [callback].
    void put(Args args) {
        static if (is(Return == void)) {
            callback(args);
            if (mainSubscriber) {
                mainSubscriber();
            }
        }
        else {
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
    }

    private void call(size_t i, Args...)(Args args) {
        if (subscribers[i]) {
            subscribers[i](args);
        }
    }
}

private alias EraseVoid(Args...) = EraseAll!(void, Args);

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

/// Combine multiple publishers to create one that waits until all of them are completed.
///
/// ---
/// auto one = pipe({
///     writeln("One finished");
/// });
/// auto two = pipe({
///     writeln("Two finished");
/// });
/// join(one, two).then({
///     writeln("Both done");
/// });
/// one();  // One finished
/// two();  // Two finished
/// // Both done
/// ---
JoinPublisher join(Publisher!()[] publishers...) {

    return new JoinPublisher(publishers);

}

@("JoinPublisher emits an event when all tasks finish")
unittest {

    int oneFinished;
    int twoFinished;
    int joinFinished;

    auto one = pipe({ oneFinished++; });
    auto two = pipe({ twoFinished++; });
    join(one, two).then!({ joinFinished++; });

    one.put();
    assert(oneFinished == 1);
    assert(joinFinished == 0);
    two.put();
    assert(twoFinished == 1);
    assert(joinFinished == 1);

}

/// Listens to a number of publishers, and as soon as all of them emit a result at least once,
/// emits an event.
///
/// Only emits events once; if a publisher emits multiple events, only the first one is used.
/// Does not publish any values on finish.
final class JoinPublisher : Publisher!() {
    mixin implementSafe;

    public {

        /// Event emitted when each publisher on the list finishes.
        Event!() onFinish;

    }

    private {

        bool[] _done;
        size_t _tasksLeft;

    }

    this(Publisher!()[] publishers...) {
        this._done = new bool[publishers.length];
        this._tasksLeft = publishers.length;

        foreach (i, publisher; publishers) {
            add(i, publisher);
        }
    }

    override void subscribe(Subscriber!() subscriber) {
        onFinish ~= subscriber;
    }

    /// Assign a publisher to listen to by index.
    private void add(size_t i, Publisher!() publisher) {
        publisher.subscribe({ emit(i); });
    }

    /// Mark a task as finished using its index.
    ///
    /// Does nothing if the task has already finished. Counts the number of tasks that remains to be completed,
    /// and if all have, emits an event.
    private void emit(size_t i) {
        if (_done[i]) return;

        _done[i] = true;
        _tasksLeft--;

        if (_tasksLeft == 0) {
            onFinish();
        }
    }

}
