// File: src/main/java/com/stayrior/vanish/VanishPlugin.java
package com.stayrior.vanish;

import org.bukkit.Bukkit;
import org.bukkit.ChatColor;
import org.bukkit.GameMode;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.command.TabCompleter;
import org.bukkit.command.TabExecutor;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.event.player.PlayerGameModeChangeEvent;
import org.bukkit.plugin.java.JavaPlugin;
import org.bukkit.potion.PotionEffect;
import org.bukkit.potion.PotionEffectType;
import org.bukkit.scoreboard.Scoreboard;
import org.bukkit.scoreboard.ScoreboardManager;
import org.bukkit.scoreboard.Team;

import java.util.*;

public class VanishPlugin extends JavaPlugin implements Listener, TabExecutor {
    private final Set<UUID> vanished = new HashSet<>();
    private final Map<UUID, ChatColor> outlineColor = new HashMap<>();
    private Scoreboard scoreboard;

    @Override
    public void onEnable() {
        getLogger().info("VanishPlugin enabled");
        Bukkit.getPluginManager().registerEvents(this, this);

        ScoreboardManager manager = Bukkit.getScoreboardManager();
        if (manager != null) scoreboard = manager.getMainScoreboard();
        else scoreboard = Bukkit.getScoreboardManager().getNewScoreboard();

        // register command in code (plugin.yml also required)
        Objects.requireNonNull(getCommand("vanish")).setExecutor(this);
        Objects.requireNonNull(getCommand("vanish")).setTabCompleter(this);

        // Ensure teams for common colors exist
        for (ChatColor c : Arrays.asList(ChatColor.RED, ChatColor.BLUE, ChatColor.GREEN, ChatColor.YELLOW, ChatColor.GOLD, ChatColor.LIGHT_PURPLE, ChatColor.AQUA, ChatColor.WHITE)) {
            ensureTeamForColor(c);
        }

        // apply noclip to online creative players (on reload)
        for (Player p : Bukkit.getOnlinePlayers()) applyCreativeNoclip(p);
    }

    @Override
    public void onDisable() {
        // cleanup: remove invisibility/glowing and restore collidable
        for (UUID id : vanished) {
            Player p = Bukkit.getPlayer(id);
            if (p != null && p.isOnline()) restorePlayer(p);
        }
        for (Player p : Bukkit.getOnlinePlayers()) {
            p.setCollidable(true);
        }
        getLogger().info("VanishPlugin disabled");
    }

    // Command handling: /vanish [outline <color>]
    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player)) {
            sender.sendMessage("Only players can use this command.");
            return true;
        }
        Player player = (Player) sender;

        if (args.length == 0) {
            if (!player.hasPermission("vanish.use")) {
                player.sendMessage(ChatColor.RED + "You don't have permission to use /vanish");
                return true;
            }
            toggleVanish(player);
            return true;
        }

        if (args.length >= 2 && args[0].equalsIgnoreCase("outline")) {
            if (!player.hasPermission("vanish.outline")) {
                player.sendMessage(ChatColor.RED + "You don't have permission to change outline color.");
                return true;
            }
            String colorName = args[1].toUpperCase(Locale.ROOT);
            try {
                ChatColor color = ChatColor.valueOf(colorName);
                setOutlineColor(player, color);
                player.sendMessage(ChatColor.GREEN + "Outline color set to " + color + colorName);
            } catch (IllegalArgumentException e) {
                player.sendMessage(ChatColor.RED + "Unknown color. Use names like RED, BLUE, GREEN, YELLOW, GOLD, AQUA, LIGHT_PURPLE, WHITE.");
            }
            return true;
        }

        player.sendMessage(ChatColor.RED + "Usage: /vanish or /vanish outline <color>");
        return true;
    }

    private void toggleVanish(Player p) {
        UUID id = p.getUniqueId();
        if (vanished.contains(id)) {
            vanished.remove(id);
            restorePlayer(p);
            p.sendMessage(ChatColor.GREEN + "You are now visible.");
        } else {
            vanished.add(id);
            applyVanish(p);
            p.sendMessage(ChatColor.GREEN + "You are now vanished (10% visibility simulated). Use /vanish outline <COLOR> to change outline.");
        }
    }

    private void applyVanish(Player p) {
        // Give invisibility effect. We keep particles and icon off for a cleaner effect.
        p.addPotionEffect(new PotionEffect(PotionEffectType.INVISIBILITY, Integer.MAX_VALUE, 0, false, false, false));
        // Make the player glow so an outline is visible to others
        p.setGlowing(true);

        // Put player in a default outline color team if none set
        ChatColor color = outlineColor.getOrDefault(p.getUniqueId(), ChatColor.YELLOW);
        addPlayerToColorTeam(p, color);
    }

    private void restorePlayer(Player p) {
        p.removePotionEffect(PotionEffectType.INVISIBILITY);
        p.setGlowing(false);
        removePlayerFromAllTeams(p);
    }

    private void setOutlineColor(Player p, ChatColor color) {
        outlineColor.put(p.getUniqueId(), color);
        // if currently vanished, move to the color team immediately
        if (vanished.contains(p.getUniqueId())) {
            addPlayerToColorTeam(p, color);
        }
    }

    private void ensureTeamForColor(ChatColor color) {
        String teamName = "vanish_" + color.name().toLowerCase();
        Team team = scoreboard.getTeam(teamName);
        if (team == null) {
            team = scoreboard.registerNewTeam(teamName);
        }
        // Set team color so that players get a consistent color (affects name coloring and may affect glow color on some server versions)
        try {
            team.setColor(color);
        } catch (NoSuchMethodError ignored) {
            // Older API may not support setColor; ignore if unavailable.
        }
    }

    private void addPlayerToColorTeam(Player p, ChatColor color) {
        ensureTeamForColor(color);
        // Remove from other vanish teams first
        removePlayerFromAllTeams(p);
        String teamName = "vanish_" + color.name().toLowerCase();
        Team team = scoreboard.getTeam(teamName);
        if (team != null) team.addEntry(p.getName());
    }

    private void removePlayerFromAllTeams(Player p) {
        for (Team t : scoreboard.getTeams()) {
            if (t.hasEntry(p.getName())) t.removeEntry(p.getName());
        }
    }

    // Noclip behavior for Creative players: use setCollidable(false) when in creative
    @EventHandler
    public void onJoin(PlayerJoinEvent e) {
        applyCreativeNoclip(e.getPlayer());
    }

    @EventHandler
    public void onQuit(PlayerQuitEvent e) {
        // Restore collidable state on quit to be safe
        e.getPlayer().setCollidable(true);
    }

    @EventHandler
    public void onGameModeChange(PlayerGameModeChangeEvent e) {
        Bukkit.getScheduler().runTaskLater(this, () -> applyCreativeNoclip(e.getPlayer()), 1L);
    }

    private void applyCreativeNoclip(Player p) {
        try {
            if (p.getGameMode() == GameMode.CREATIVE) {
                // In creative, allow passing through blocks by disabling collisions
                p.setCollidable(false);
                p.setAllowFlight(true);
            } else {
                p.setCollidable(true);
            }
        } catch (NoSuchMethodError ex) {
            // If setCollidable isn't available on this server API, we silently ignore.
            getLogger().warning("setCollidable API not available on this server build — creative noclip may not work.");
        }
    }

    // Tab completion for /vanish
    @Override
    public List<String> onTabComplete(CommandSender sender, Command command, String alias, String[] args) {
        if (args.length == 1) {
            return Arrays.asList("outline");
        } else if (args.length == 2 && args[0].equalsIgnoreCase("outline")) {
            List<String> names = new ArrayList<>();
            for (ChatColor c : ChatColor.values()) {
                if (c.isColor()) names.add(c.name().toLowerCase());
            }
            return names;
        }
        return Collections.emptyList();
    }
}

/*
plugin.yml (place under src/main/resources/plugin.yml):

name: VanishPlugin
main: com.stayrior.vanish.VanishPlugin
version: 1.0
api-version: 1.21
authors: [stayrior]
commands:
  vanish:
    description: Toggle vanish or change outline color
    usage: /vanish or /vanish outline <color>
permissions:
  vanish.use:
    description: Allows using /vanish
    default: op
  vanish.outline:
    description: Allows changing vanish outline color
    default: op

Notes:
- This implementation uses PotionEffectType.INVISIBILITY + glowing to simulate "10% visibility". Minecraft/Paper do not provide an easy built-in partial transparency level for players; achieving exact 10% visibility would require client-side resource packs or complex packet manipulations.
- Outline color is implemented using scoreboard teams and Team#setColor when available. Some server versions or clients may not change the glow color via teams; Paper may offer additional API (setGlowingColor) on newer builds — you can adapt the code to call that when available.
- Creative "noclip" is attempted via Player#setCollidable(false). If that API isn't present, the plugin logs a warning and the feature won't work. Many Paper builds expose this API.
- Build with Java 17+ and target Paper 1.21.1 dependencies.
*/
