import Image from "next/image";
import { FanCurve } from "./fan-curve";
import { site } from "./site";

function DownloadButton({ className = "" }: { className?: string }) {
  return (
    <a
      href={site.download}
      className={`inline-flex h-11 items-center justify-center rounded-full bg-white px-6 text-sm font-medium text-black transition-colors hover:bg-zinc-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white ${className}`}
    >
      Download for Mac
    </a>
  );
}

const safety = [
  ["Clamped to your hardware", "Whatever is sent, speeds stay inside the range your fans report."],
  ["Full speed above 95°C", "A hot chip overrides your settings every time."],
  ["Hands the fans back", "When the helper stops, for any reason, macOS takes over first."],
];

const steps = [
  ["Download", "Get the latest .dmg from GitHub Releases."],
  ["Drag to Applications", "Open Sirocco. The fan appears in your menu bar."],
  ["Allow it once", "Switch on Sirocco under Allow in the Background in System Settings."],
];

export default function Home() {
  return (
    <div className="mx-auto max-w-6xl overflow-x-clip px-6">
      <header className="flex h-16 items-center justify-between">
        <a href="#" className="flex items-center gap-2.5 text-[15px] font-semibold">
          <Image src="/icon.png" alt="" width={28} height={28} />
          {site.name}
        </a>
        <nav className="flex items-center gap-6 text-sm text-zinc-400">
          <a href="#how" className="hidden transition-colors hover:text-white sm:block">
            How it works
          </a>
          <a href="#install" className="hidden transition-colors hover:text-white sm:block">
            Install
          </a>
          <a href={site.repo} className="transition-colors hover:text-white">
            GitHub
          </a>
        </nav>
      </header>

      <main>
        {/* Hero */}
        <section className="grid items-center gap-14 pb-24 pt-16 md:grid-cols-[1.15fr_1fr] md:pt-24">
          <div>
            <p className="font-mono text-xs uppercase tracking-[0.18em] text-zinc-500">
              Fan control for Apple silicon
            </p>
            <h1 className="mt-5 text-5xl font-semibold leading-[1.05] tracking-tight text-balance sm:text-6xl">
              A cool breeze for a{" "}
              <span className="bg-gradient-to-r from-cool to-warm bg-clip-text text-transparent">hot Mac</span>
            </h1>
            <p className="mt-6 max-w-xl text-lg leading-relaxed text-zinc-400 text-pretty">
              Sirocco spins your fans up earlier, on a curve you set, while you&apos;re plugged in and at your Mac. The
              rest of the time macOS runs them as it always does.
            </p>
            <div className="mt-9 flex flex-wrap items-center gap-4">
              <DownloadButton />
              <a
                href={site.repo}
                className="inline-flex h-11 items-center rounded-full border border-line px-6 text-sm font-medium text-zinc-200 transition-colors hover:border-white/20 hover:text-white"
              >
                View source
              </a>
            </div>
            <p className="mt-6 text-[13px] text-zinc-500">
              Free and open source. macOS 13 or later. Signed and notarized by Apple.
            </p>
          </div>

          <div className="relative mx-auto w-full max-w-[330px]">
            <div
              aria-hidden
              className="absolute -inset-16 rounded-full bg-[radial-gradient(closest-side,rgb(143_193_255/0.16),transparent)] blur-2xl"
            />
            <div
              aria-hidden
              className="absolute -bottom-20 -right-24 size-72 rounded-full bg-[radial-gradient(closest-side,rgb(255_184_148/0.12),transparent)] blur-2xl"
            />
            <Image
              src="/panel.png"
              alt="The Sirocco panel: chip temperature, fan speed, mode and fan curve settings"
              width={660}
              height={1186}
              preload
              className="relative w-full drop-shadow-2xl"
            />
          </div>
        </section>

        {/* Why */}
        <section id="how" className="grid gap-12 border-t border-line py-24 md:grid-cols-2 md:gap-20">
          <div>
            <h2 className="text-3xl font-semibold tracking-tight text-balance">Cool the case before it gets hot</h2>
            <p className="mt-5 leading-relaxed text-zinc-400 text-pretty">
              A MacBook keeps its fans near minimum until the chip is hot. Under steady work the aluminium soaks up that
              heat and the case gets uncomfortable to touch.
            </p>
            <p className="mt-4 leading-relaxed text-zinc-400 text-pretty">
              Sirocco starts the climb sooner. You choose where the ramp begins, where it reaches full speed, and how
              fast the fans may go.
            </p>
          </div>
          <FanCurve />
        </section>

        {/* Features */}
        <section className="border-t border-line py-24">
          <h2 className="max-w-xl text-3xl font-semibold tracking-tight text-balance">
            Only when it helps, and out of the way otherwise
          </h2>

          <div className="mt-12 grid gap-4 md:grid-cols-6">
            <article className="overflow-hidden rounded-2xl border border-line bg-surface md:col-span-4 md:row-span-2">
              <div className="p-7">
                <h3 className="font-medium">Smart mode</h3>
                <p className="mt-2 max-w-md text-sm leading-relaxed text-zinc-400">
                  Fans follow your curve only while you&apos;re on power and using the Mac. Unplug or walk away and
                  macOS takes over again.
                </p>
              </div>
              <Image
                src="/settings.png"
                alt="Sirocco settings window showing live fan readings and the Smart, Max and Off modes"
                width={1440}
                height={1040}
                className="ml-7 w-[calc(100%-1.75rem)] rounded-tl-xl border-l border-t border-line"
              />
            </article>

            <article className="rounded-2xl border border-line bg-surface p-7 md:col-span-2">
              <h3 className="font-medium">Presets</h3>
              <p className="mt-2 text-sm leading-relaxed text-zinc-400">
                Quiet, Balanced and Cool, scaled to your Mac&apos;s own fan range.
              </p>
              <div className="mt-6 flex gap-2 font-mono text-xs">
                {["Quiet", "Balanced", "Cool"].map((preset, i) => (
                  <span
                    key={preset}
                    className={`rounded-full border px-3 py-1.5 ${
                      i === 1 ? "border-white/25 text-white" : "border-line text-zinc-500"
                    }`}
                  >
                    {preset}
                  </span>
                ))}
              </div>
            </article>

            <article className="rounded-2xl border border-line bg-surface p-7 md:col-span-2">
              <h3 className="font-medium">Lives in the menu bar</h3>
              <p className="mt-2 text-sm leading-relaxed text-zinc-400">
                A fan icon that turns with the real fans, with temperature and speed beside it if you want them.
              </p>
              <p className="mt-6 font-mono text-sm text-zinc-300">
                47° <span className="text-zinc-600">/</span> 3.5k
              </p>
            </article>

            <article className="rounded-2xl border border-line bg-surface p-7 md:col-span-3">
              <h3 className="font-medium">Max and Off</h3>
              <p className="mt-2 text-sm leading-relaxed text-zinc-400">
                Pin the fans at your maximum for a heavy job, or hand them back to macOS entirely.
              </p>
            </article>

            <article className="rounded-2xl border border-line bg-surface p-7 md:col-span-3">
              <h3 className="font-medium">Private by default</h3>
              <p className="mt-2 text-sm leading-relaxed text-zinc-400">
                Sirocco collects nothing. Its only network request is the update check, and updates are signed and
                verified before they install.
              </p>
            </article>
          </div>
        </section>

        {/* Safety */}
        <section className="grid gap-12 border-t border-line py-24 md:grid-cols-[1fr_1.4fr] md:gap-20">
          <div>
            <h2 className="text-3xl font-semibold tracking-tight text-balance">Built to fail safe</h2>
            <p className="mt-5 leading-relaxed text-zinc-400 text-pretty">
              Changing fan speeds needs root, so a small helper inside the app does that and nothing else. The app and
              the helper each check the other&apos;s code signature before they talk.
            </p>
          </div>
          <dl className="divide-y divide-line border-y border-line">
            {safety.map(([title, body]) => (
              <div key={title} className="grid gap-1 py-5 sm:grid-cols-[14rem_1fr] sm:gap-6">
                <dt className="font-medium">{title}</dt>
                <dd className="text-sm leading-relaxed text-zinc-400">{body}</dd>
              </div>
            ))}
          </dl>
        </section>

        {/* Install */}
        <section id="install" className="border-t border-line py-24">
          <h2 className="text-3xl font-semibold tracking-tight">Three steps, one of them once</h2>
          <ol className="mt-12 grid gap-10 md:grid-cols-3">
            {steps.map(([title, body], i) => (
              <li key={title}>
                <span className="font-mono text-xs text-zinc-500">0{i + 1}</span>
                <h3 className="mt-3 font-medium">{title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-zinc-400">{body}</p>
              </li>
            ))}
          </ol>
          <div className="mt-14 flex flex-wrap items-center gap-5">
            <DownloadButton />
            <p className="text-[13px] text-zinc-500">Needs Apple silicon and a Mac with fans.</p>
          </div>
        </section>
      </main>

      <footer className="flex flex-col gap-4 border-t border-line py-10 text-[13px] text-zinc-500 sm:flex-row sm:items-center sm:justify-between">
        <p>© 2026 Joy Madhu. MIT licensed.</p>
        <nav className="flex gap-6">
          <a href={site.repo} className="transition-colors hover:text-white">
            GitHub
          </a>
          <a href={`${site.repo}/releases`} className="transition-colors hover:text-white">
            Releases
          </a>
          <a href={`${site.repo}/blob/main/CHANGELOG.md`} className="transition-colors hover:text-white">
            Changelog
          </a>
          <a href={`${site.repo}/security`} className="transition-colors hover:text-white">
            Security
          </a>
        </nav>
      </footer>
    </div>
  );
}
