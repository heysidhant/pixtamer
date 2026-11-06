// Replays the hero export and copies the Homebrew commands. The page works without this file.
const map = document.querySelector(".map");
const replay = document.querySelector(".replay");

if (map && replay && matchMedia("(prefers-reduced-motion: no-preference)").matches) {
  const watcher = new IntersectionObserver(
    ([entry]) => {
      if (!entry.isIntersecting) return;
      map.classList.add("is-playing");
      watcher.disconnect();
    },
    { threshold: 0.6 },
  );
  watcher.observe(map);

  replay.hidden = false;
  replay.addEventListener("click", () => {
    map.classList.remove("is-playing");
    void map.offsetWidth; // Restart the CSS animation.
    map.classList.add("is-playing");
  });
}

const copy = document.querySelector(".copy");
const commands = document.querySelector("#brew-commands");

if (copy && commands && navigator.clipboard) {
  copy.hidden = false;
  copy.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(commands.textContent.trim());
      copy.textContent = "Copied";
    } catch {
      copy.textContent = "Select the text to copy";
    }
    setTimeout(() => {
      copy.textContent = "Copy";
    }, 2400);
  });
}
