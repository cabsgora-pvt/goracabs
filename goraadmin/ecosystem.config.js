module.exports = {
  apps: [
    {
      name: 'goraadmin',
      cwd: '/var/www/goraadmin/goraadmin',
      script: 'node_modules/next/dist/bin/next',
      args: 'start -p 3000',
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      max_memory_restart: '600M',
      env: {
        NODE_ENV: 'production',
        PORT: 3000,
      },
      log_date_format: 'YYYY-MM-DD HH:mm:ss',
      error_file: '/var/log/goraadmin-error.log',
      out_file: '/var/log/goraadmin-out.log',
    },

    // ── Scheduled: rebuild the ETA speed profile ──────────────────────────────
    // The ETA engine reads learned speeds from the SpeedProfile collection, and
    // /api/cron/speed-profile is the only thing that ever writes it. Nothing was
    // scheduled to call it, so the collection stayed empty and every ETA on the
    // platform used the flat DEFAULT_SPEED_KMPH fallback.
    //
    // autorestart:false + cron_restart is PM2's one-shot scheduled-job pattern:
    // the process runs, exits, and PM2 starts it again at the next cron tick
    // instead of immediately.
    //
    // 03:15 daily — after the overnight lull, so the previous day's rides are
    // all settled. The job is a full recompute and is safe to run repeatedly.
    {
      name: 'goraadmin-speed-cron',
      cwd: '/var/www/goraadmin/goraadmin',
      script: 'scripts/speed-profile-cron.js',
      instances: 1,
      exec_mode: 'fork',
      autorestart: false,
      cron_restart: '15 3 * * *',
      env: {
        NODE_ENV: 'production',
        // The job talks to the app over loopback; override if the port moves.
        CRON_TARGET_URL: 'http://127.0.0.1:3000',
      },
      log_date_format: 'YYYY-MM-DD HH:mm:ss',
      error_file: '/var/log/goraadmin-speed-cron-error.log',
      out_file: '/var/log/goraadmin-speed-cron-out.log',
    },
  ],
}
