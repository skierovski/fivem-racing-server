# BlackList Racing - FiveM Server

NFS Most Wanted inspired chase/run racing server for the Polish racing community.

## Features

- **Custom Loading Screen** - Cinematic NFS MW themed loading experience
- **Discord Verification** - Must have verified role to connect
- **Full-Screen Menu** - No GTA lobby, custom NUI with Ranked / Normal / Free Roam
- **Ranked 1v1** - Chase vs Run with Elo-based MMR
- **Tier System** - Bronze / Silver / Gold / Platinum / Diamond / BlackList (top 20)
- **Normal Chase** - 1 runner vs up to 4 chasers, bank heist themed
- **Free Roam** - Ghosted solo driving practice
- **Vehicle Tuning** - Tier-locked car pools with visual customization
- **Anti-Cheat** - Anti-ram and anti-jump enforcement
- **In-Menu Chat** - Chat with tier badges

## Requirements

- FiveM Server (txAdmin recommended)
- MySQL / MariaDB
- [oxmysql](https://github.com/overextended/oxmysql) resource
- Discord Bot Token (for role verification)

## Setup

1. Clone this repo into your FiveM server directory
2. Import `sql/schema.sql` into your MySQL database
3. Copy `server.cfg` and fill in your credentials:
   - `sv_licenseKey`
   - `discord_bot_token`, `discord_guild_id`, `discord_required_role_id`
   - `mysql_connection_string`
4. Download and place [oxmysql](https://github.com/overextended/oxmysql/releases) in `resources/`
5. Start the server

## Resource Structure

| Resource | Description |
|----------|-------------|
| `[loadingscreen]` | Custom cinematic loading screen |
| `[discord]` | Discord role verification gate |
| `[base]` | Spawn control, disable GTA lobby |
| `[menu]` | Full-screen NUI main menu |
| `[chat]` | In-menu chat system |
| `[ranked]` | Tier/MMR system + BlackList |
| `[vehicles]` | Car pools per tier + tuning |
| `[matchmaking]` | Queue system for all modes |
| `[chase]` | Chase/Run game mode logic |
| `[freeroam]` | Ghosted free driving |
| `[handling]` | Custom vehicle handling |
| `[anticheat]` | Anti-ram / anti-jump |
