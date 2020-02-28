+++
title="Fixing Jitter - Timestep Issues"
date=2019-08-19
+++

## Intro

While working on [Cala](https://libcala.github.io), I noticed something strange about how timesteps are usually handled, and a way to fix an issue with them.  A little bit of background first: a timestep (delta time) is how much time passes between each frame in a game or animation.  In the early days games didn't handle this correctly.  They would develop for whatever computer system was popular at the time and set a fixed delta time.

<!-- more -->

```rust
fn game_loop() {
    // Delta Time: all modern computers will run this game at 30 FPS.
    let dt = 33; // 33 milliseconds.

    // Physics calculations.
    ...
}

fn main() {
    loop {
        game_loop();
        // Redraw
        ...
    }
}
```

The issue with this is that in following years computers would become twice as fast.  And, when that happens you are running your physics calculations twice as many times - which means all animations in the game are double speed!  Hopefully, you can see how that could be a problem.  Hardware manufacturers tried to fix it by adding a [turbo button](https://en.wikipedia.org/wiki/Turbo_button) on computers.  Basically, press the turbo button, and your computer runs twice as slow, making old video games playable again.

## Modern Timestep Calculations
In order to never have this problem again, a new method became commonplace for calculating delta time.

```rust
fn game_loop(prev_time: &mut u64) {
    let this_time = get_system_millis();
    // Delta Time: how much time has passed since previous frame.
    let dt = this_time - prev_time;
    // Set last time to this time
    *prev_time = this_time;

    // Physics calculations.
    ...
}

fn main() {
    let mut prev_time = get_system_millis();

    loop {
        game_loop(&mut prev_time);
        // Redraw
        ...
    }
}
```

And this is the method that's used in all of the video games that you play today.  But, it has a few issues (and you've probably noticed).  Since the first way of calculating delta time has gone out of style, computers started being made with multiple processors: dual-core, quad-core, etc.  And [schedulers](https://en.wikipedia.org/wiki/Scheduling_(computing)) started becoming more complicated.  Now, at any point another process can start taking up more CPU time away from the video game you're playing.  This means that your frame rate is more likely to fluctuate (so it might average 30fps, but at some points you might be getting 12).  But this is not an issue yet, because humans can only really see 12 FPS.  The reason 12FPS is unacceptable to gamers is because of jitter.

### Issue #1: Motion Blur
If you play a game at 12 FPS, animations will not feel very smooth.  This is because there's no motion blur.  Live action movies are often 24 FPS, but it looks perfectly normal - and the reason is motion blur.  If you capture a frame of a movie, chances are it will look blurry because the subjects are moving.  In a video game, rendering motion blur is computationally expensive, so video games don't do that.  Instead, they emulate it by trying to get a higher frame rate.  That's why gaming rigs designed to get 144FPS exist, even though no one can see that many frames per second.  But it's only one reason.  Lack of motion blur isn't the only cause of jitter.

### Issue #2: Unpredictability
What Is Delta Time?  Let's look back at our code from earlier.

```rust
fn game_loop(prev_time: &mut u64) {
    let this_time = get_system_millis();
    // Delta Time: how much time has passed since previous frame.
    let dt = this_time - prev_time;
    // Set last time to this time
    *prev_time = this_time;

    // Physics calculations.
    ...
}
```

Delta time is *how much time has passed since previous frame*.  That sounds like what we want, but when we're calculating it is key.  We're calculating it at the beginning of our game loop, before we redraw.  But, we don't know how long it's going to take to redraw.  What we really want is how long between last monitor refresh and this monitor refresh, but we're getting how long between 2 monitor refreshes ago and the last monitor refresh.  Wait, why are we getting that?  Because the last thing that happens in our `loop` is a monitor refresh, and immediately after that we call `get_system_millis()`.  Ideally, we'd want to call `get_system_millis()` right before to see how long our rendering just took, but we need that information to do our physics calculations, which we then need to redraw; therefore it is impossible.  Luckily as long as our frame rate stays consistent, this is not an issue, but if your frame rate fluctuates, this will create jitter and make you feel like the frame rates not high enough.  And, yes, if you can increase the frame rate the jitter will be less noticeable.

Ultimately, what you want though, is to be able to predict how long it will take for you to render.  This, is unfortunately impossible with modern operating systems running hundreds of background tasks at once, that may take a large chunk of CPU time at any moment.  The only way to fix it is to limit background processes, which probably means making a new OS (and that's a lot of work).

### Issue #3: Monitor Refresh Rate
Now, we get to the whole purpose of this blog post.  The 3rd cause of jitter: the CPU's time clock is not synchronized with the monitor's time clock.  Running the code for modern timestep calculations we get something like this (SPF is seconds per frame, inverse of FPS):

> SPF 0.033999998, FPS 29.411766
> SPF 0.031999998, FPS 31.250002
> SPF 0.033999998, FPS 29.411766
> SPF 0.031999998, FPS 31.250002
> SPF 0.031999998, FPS 31.250002
> SPF 0.033999998, FPS 29.411766
> SPF 0.033999998, FPS 29.411766
> SPF 0.033, FPS 30.30303
> SPF 0.033, FPS 30.30303
> SPF 0.033999998, FPS 29.411766

It looks like the frame rate is fluctuating from this output, but guess what?  It's actually not.  The actual perceived seconds per frame will always be a multiple of the inverse of your monitor's refresh rate.  My monitor's refresh rate is about 59.9 Hertz (refreshes per second).  Now take the inverse of that and convert to nanoseconds.

- Every 16674170 nanoseconds is 1 monitor refresh.
- Every 33348340 nanoseconds is 2 monitor refreshes.
- Every 50022510 nanoseconds is 3 monitor refreshes.

So, the game's running a little slow on my computer.  The screen is only getting updated every other monitor refresh.  Luckily, for this run, we have avoided issue #2 so far.  But as soon as we miss 2 monitor refreshes instead of 1 we'll get some jitter.  But, we are still getting a small case of jitter.

First problem: we're using milliseconds, and monitor refresh needs, for my monitor, 10 nanosecond accuracy to be right on.  Second problem is our timing is on the CPU, not on the monitor.  The CPU is a good approximation, but in reality the monitor refresh rate is very steady.  Therefore, I can eliminate this form of jitter with the following code:

```rust
fn game_loop(prev_time: &mut u64, refresh_rate: u64) {
    let this_time = get_system_millis();
    // Delta Time: how much time has passed since previous frame.
    let dt_approx = this_time - prev_time;
    // Set last time to this time
    *prev_time = this_time;
    // Find the exact amount of time between monitor refreshes.
    let tmp = dt_approx + refresh_rate / 2;
    let dt = tmp - (tmp % refresh_rate);

    // Physics calculations.
    ...
}

fn main() {
    let mut prev_time = get_system_millis();
    let refresh_rate = get_monitor_refresh();

    loop {
        game_loop(&mut prev_time, refresh_rate);
        // Redraw
        ...
    }
}
```

Basically, we use the approximation given by the CPU timer to figure out how much time has passed between monitor refreshes.  Our previous results would become these new results (in nanoseconds per frame), leading to smoother animation:

> NPF 33348340
> NPF 33348340
> NPF 33348340
> NPF 33348340
> NPF 33348340
> NPF 33348340
> NPF 33348340
> NPF 33348340
> NPF 33348340
> NPF 33348340

## Conclusion
Not all of the issues were fixed, but fixing one case of jitter should make the gameplay experience a lot nicer.  Maybe at some point, a motion blur algorithm will become efficient and accurate enough that we won't be able to tell the difference between 144fps and 12fps with motion blur, but I wouldn't count on it.  Operating systems used to be a lot more predictable as to when they'd take up CPU time.  And, maybe some day there will an operating system that can run a game without background processes that can cause random latency.  Sadly, until that day comes our modern, faster computers will feel slower than older, slower computers.

> *Feel free to email me any corrections in grammar or spelling at jeronlau@plopgrizzly.com.*
