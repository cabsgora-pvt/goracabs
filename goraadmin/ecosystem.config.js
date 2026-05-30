module.exports = {
  apps: [
    {
      name: 'goraadmin',
      cwd: '/var/www/goraadmin/goradmin',
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
  ],
}
