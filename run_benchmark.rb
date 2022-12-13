require 'benchmark'
require 'json'

abort "Usage: run_benchmarks.rb [compiler_name]" if ARGV.size < 1

def cpuname()
  cpuinfo = File.read("/proc/cpuinfo")
  if cpuinfo =~ /^model\s+name\s*\:\s*(.*)/
    return $1.gsub(/\s+/, " ").strip
  end
end

iota_counter_100m = <<~'HEREDOC'
    /+dub.sdl: dependency "speedy-stdio" path="." +/
    @safe:
    import std.stdio;
    void main() {
      import std.range;
      100000001.iota.writefln!"%(%d\n%)";
    }
    HEREDOC

foreach_counter_100m = <<~'HEREDOC'
    /+dub.sdl: dependency "speedy-stdio" path="." +/
    @safe:
    import std.stdio;
    void main() {
      foreach (i ; 0 .. 100000001)
        writeln(i);
    }
    HEREDOC

bottles_100k =  <<~'HEREDOC'
    /+dub.sdl: dependency "speedy-stdio" path="." +/
    @safe:
    import std.stdio;
    const repeats = 100000;

    void main() {
      foreach (i ; 0 .. repeats) {
        auto bottles(int n) { return n == 1 ? " bottle" : " bottles"; }
        foreach_reverse(n ; 1 .. 100) {
          writefln!"%d%s of beer on the wall, %d%s of beer."(n, bottles(n), n, bottles(n));
          static immutable a = ["Take", "one", "down", "and", "pass", "it", "around"];
          a.writef!"%-(%s %), ";
          if (n - 1 <= 0)
            write("no more bottles");
          else
            write(n - 1, bottles(n - 1));
          writeln(" of beer on the wall.");
          writeln;
        }
        writeln("No more bottles of beer on the wall, no more bottles of beer.");
        writeln("Go to the store and buy some more, 99 bottles of beer on the wall.");
      }
    }
    HEREDOC

def run_benchmark(name, code, compiler, extra_dflags = "")
  compiler_version = `#{compiler} --version`.split("\n")[0].strip
  times = {}
  speedy_ver = "?"
  ["std.stdio", "speedy.stdio", "speedy.fakestdio"].each do |modulename|
    File.write("benchmark.d", code.sub(/import\s+std\.stdio\;/, "import #{modulename};"))
    if extra_dflags != ""
      result = `DFLAGS="#{extra_dflags}" dub build --build=release --single --force --compiler=#{compiler} benchmark.d`
    else
      result = `dub build --build=release --single --force --compiler=#{compiler} benchmark.d`
    end
    abort "build failure" unless $?.success?
    if result =~ /^speedy\-stdio (.*)\: building configuration \"library\"/
      speedy_ver = $1.strip
    end
    a = 5.times.map { Benchmark.measure { `./benchmark > /dev/null` } }
    a.sort! {|x, y| (x.cutime + x.cstime) <=> (y.cutime + y.cstime) }
    times[modulename] = a[0].cutime + a[0].cstime
  end
  return JSON.generate({test_name: name, compiler: compiler_version, cpu: cpuname, times: times, speedy_ver: speedy_ver, extra_dflags: extra_dflags})
end

extra_dflags = ARGV.size >= 2 ? ARGV[1] : ""

puts run_benchmark("bottles_100k", bottles_100k, ARGV[0], extra_dflags)
puts run_benchmark("iota_counter_100m", iota_counter_100m, ARGV[0], extra_dflags)
puts run_benchmark("foreach_counter_100m", foreach_counter_100m, ARGV[0], extra_dflags)
