// An illustration, not measured data: macOS holds the fans low until the chip is hot,
// Sirocco starts the climb earlier on the curve the user sets.
export function FanCurve() {
  return (
    <figure>
      <svg viewBox="0 0 520 260" role="img" aria-labelledby="curve-title" className="w-full">
        <title id="curve-title">
          Fan speed against chip temperature. macOS stays low until the chip is hot, Sirocco ramps up earlier.
        </title>
        {[40, 110, 180].map((y) => (
          <line key={y} x1="0" x2="520" y1={y} y2={y} stroke="rgb(255 255 255 / 0.06)" />
        ))}
        <line x1="0" x2="520" y1="220" y2="220" stroke="rgb(255 255 255 / 0.14)" />

        {/* macOS: flat, then a late climb */}
        <path
          d="M0 196 H330 C380 196 410 150 450 70 L520 52"
          fill="none"
          stroke="rgb(255 255 255 / 0.28)"
          strokeWidth="2"
          strokeDasharray="5 6"
          strokeLinecap="round"
        />
        {/* Sirocco: an early, even ramp */}
        <defs>
          <linearGradient id="ramp" x1="0" x2="1">
            <stop offset="0" stopColor="#8fc1ff" />
            <stop offset="1" stopColor="#ffb894" />
          </linearGradient>
        </defs>
        <path
          d="M0 168 H150 L400 60 H520"
          fill="none"
          stroke="url(#ramp)"
          strokeWidth="2.5"
          strokeLinecap="round"
          strokeLinejoin="round"
        />

        <g className="font-mono" fontSize="11" fill="rgb(255 255 255 / 0.45)">
          <text x="0" y="244">40°</text>
          <text x="150" y="244" textAnchor="middle">55°</text>
          <text x="400" y="244" textAnchor="middle">80°</text>
          <text x="520" y="244" textAnchor="end">100°</text>
        </g>
      </svg>
      <figcaption className="mt-4 flex flex-wrap gap-x-6 gap-y-2 text-[13px] text-zinc-400">
        <span className="flex items-center gap-2">
          <span className="h-0.5 w-5 rounded bg-gradient-to-r from-cool to-warm" />
          Sirocco, on your curve
        </span>
        <span className="flex items-center gap-2">
          <span className="h-0 w-5 border-t-2 border-dashed border-white/30" />
          macOS on its own
        </span>
        <span className="text-zinc-500">Illustration</span>
      </figcaption>
    </figure>
  );
}
