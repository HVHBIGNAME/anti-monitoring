# 🕵️ Anti-Monitoring

**Удаляет агенты слежки и мониторинга от хостинг-провайдеров и систем виртуализации.**

Отключает удалённый доступ, телеметрию и мониторинг, которые позволяют владельцам хостинга:
- 👁️ Получать доступ к серверу через консоль панели
- 🔐 Сбрасывать пароли без вашего ведома
- 📊 Собирать метрики и телеметрию
- 💾 Управлять резервными копиями
- 🔧 Автоматически настраивать систему

---

## ⚡ Быстрая установка (одна команда)

```bash
curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/install.sh | sudo bash -s -- --silent --force
```

**Эта команда:**
- ✅ Автоматически установит зависимости (curl/wget)
- ✅ Скачает и установит скрипт
- ✅ Удалит все агенты мониторинга
- ✅ Без вопросов и подтверждений

---

## 🛡️ Что удаляется

### Виртуализация
- **QEMU Guest Agent** — доступ к VM через хост
- **VMware Tools** — управление виртуальной машиной
- **VirtualBox Guest Additions** — интеграция с хостом
- **Hyper-V Integration Services** — мониторинг Hyper-V

### Cloud провайдеры
- **Cloud-Init** — автоконфигурация при создании
- **AWS CloudWatch + SSM Agent** — мониторинг Amazon
- **Google Cloud Guest Agent** — управление GCP
- **Azure Linux Agent** — мониторинг Microsoft Azure
- **DigitalOcean Agent** — панель управления DO
- **Vultr Agent** — консоль Vultr
- **Hetzner Cloud Agent** — мониторинг Hetzner
- **Linode Agent** — управление Linode

### Телеметрия
- **Ubuntu Advantage** — отправка данных Canonical
- **Landscape Client** — корпоративный мониторинг
- **Apport** — отчёты о сбоях

---

## 📦 Варианты установки

### 1️⃣ Полностью автоматическая (рекомендуется)
```bash
curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/install.sh | sudo bash -s -- --silent --force
```

### 2️⃣ С автоустановкой зависимостей
```bash
curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/install.sh | sudo bash -s -- --auto-deps
```

### 3️⃣ Интерактивная (с вопросами)
```bash
curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/install.sh | sudo bash
```

### 4️⃣ Только посмотреть что будет удалено (dry-run)
```bash
curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/antimon.sh | sudo bash -s -- --dry-run
```

### Доступные флаги

**Для install.sh:**
- `--auto-deps` — автоматически установить недостающие зависимости
- `--silent` — полностью автоматическая установка без вывода (включает --auto-deps)
- `--force` — пропустить все подтверждения
- `--help` — показать справку

**Для antimon.sh:**
- `--dry-run` — показать что будет удалено без реальных изменений
- `--force` — пропустить подтверждения
- `--help` — показать справку

---

## ⚠️ КРИТИЧЕСКИ ВАЖНО!

### После удаления агентов НЕ БУДУТ РАБОТАТЬ:

❌ **Консоль из панели хостинга** (VNC/Console)  
❌ **Сброс пароля через панель**  
❌ **Автоматические бэкапы через панель**  
❌ **Мониторинг метрик сервера**  
❌ **Автоматическая настройка сети (Cloud-Init)**  
❌ **Алерты от провайдера**  

### Останется работать:

✅ SSH доступ (твой основной способ подключения)  
✅ Все твои сервисы и приложения  
✅ Сеть (если уже настроена)  
✅ Файловая система и данные  

### ⚡ Перед использованием:

1. **Убедись что есть SSH доступ** — после удаления консоль не будет работать!
2. **Запиши данные для входа** — сброс пароля через панель станет невозможен
3. **Сделай бэкап** — на случай если что-то пойдёт не так
4. **Проверь dry-run** — посмотри что будет удалено

---

## 🗑️ Удаление

```bash
curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/uninstall.sh | sudo bash
```

**Важно:** Удаление скрипта **НЕ ВОССТАНОВИТ** агенты мониторинга!  
Для восстановления используй панель управления хостинга или переустанови систему.

---

## 📋 Ручной запуск

```bash
# После установки скрипт сохраняется в скрытой директории
bash ~/.cache/system/.antimon

# С флагами
bash ~/.cache/system/.antimon --dry-run  # Просмотр без изменений
bash ~/.cache/system/.antimon --force    # Без подтверждений
```

---

## 🔧 Требования

- **ОС:** Linux (Debian, Ubuntu, CentOS, RHEL, Fedora, Arch)
- **Зависимости:** curl или wget (устанавливаются автоматически с `--auto-deps`)
- **Права:** sudo/root для удаления агентов

---

## 💡 Когда использовать

### ✅ Используй если:
- Хочешь полный контроль над сервером
- Не доверяешь хостинг-провайдеру
- Нужна максимальная приватность
- Работаешь с конфиденциальными данными
- У тебя есть альтернативный доступ (SSH)

### ❌ НЕ используй если:
- Полагаешься на консоль панели хостинга
- Нужен сброс пароля через панель
- Используешь автоматические бэкапы провайдера
- Не уверен в своих действиях
- Не имеешь надёжного SSH доступа

---

## 🚀 Примеры использования

### Быстрая установка на новом сервере
```bash
# 1. Подключись по SSH
ssh root@your-server-ip

# 2. Запусти установку
curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/install.sh | sudo bash -s -- --silent --force

# 3. Перезагрузи (рекомендуется)
sudo reboot
```

### Проверка перед удалением
```bash
# Посмотри что будет удалено
curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/antimon.sh | sudo bash -s -- --dry-run

# Если всё ок, удали
curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/install.sh | sudo bash -s -- --force
```

### Установка с вопросами
```bash
# Установщик спросит:
# - Установить ли недостающие зависимости? (Y/n)
# - Запустить ли удаление агентов? (yes/no)
curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/install.sh | sudo bash
```

---

## 🛡️ Что происходит под капотом

1. **Остановка сервисов** — `systemctl stop/disable/mask`
2. **Удаление пакетов** — через apt/yum/dnf/pacman
3. **Убийство процессов** — `pkill -9`
4. **Удаление файлов** — конфиги, данные, логи
5. **Блокировка переустановки** — `apt-mark hold`

---

## 📊 Статистика удаления (на тестовом сервере)

```
✓ QEMU Guest Agent     — не найден
✓ Cloud-Init           — удалено (3 сервиса)
✓ VMware Tools         — удалено
✓ Vultr Agent          — удалено
✓ Landscape            — удалено
✓ Apport               — отключено

Всего удалено: 7 компонентов
Освобождено: ~45MB
Время выполнения: 8 секунд
```

---

## 🔍 Дополнительная защита

После удаления агентов рекомендуется:

1. **Очистить kernel ring buffer**
   ```bash
   dmesg -c > /dev/null
   ```

2. **Проверить удалённый syslog**
   ```bash
   grep -v "^#" /etc/rsyslog.conf | grep "@"
   ```

3. **Очистить SSH следы**
   ```bash
   # Удали добавленные ключи
   nano ~/.ssh/authorized_keys
   
   # Очисти known_hosts
   cat /dev/null > ~/.ssh/known_hosts
   ```

4. **Перезагрузить сервер**
   ```bash
   sudo reboot
   ```

5. **Использовать server-cleaner для логов**
   ```bash
   # Дополнительный инструмент для очистки логов
   curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/server-cleaner/main/install.sh | bash -s -- --silent
   ```

---

## 📁 Структура установки

```
~/.cache/system/
└── .antimon    # Основной скрипт удаления агентов
```

**Расположение скрыто**, чтобы не привлекать внимание.

---

## ⚠️ Предупреждение

Этот инструмент предназначен для **легального использования** на собственных серверах или с явного разрешения владельца.

**Не используйте** для:
- Сокрытия следов несанкционированного доступа
- Обхода политик безопасности организации
- Нарушения условий обслуживания хостинг-провайдера
- Любых незаконных действий

**После удаления агентов:**
- Хостинг-провайдер не сможет помочь через консоль
- Автоматические системы защиты могут не работать
- Техподдержка может отказать в помощи
- Некоторые функции панели управления станут недоступны

**Используй только если:**
- Понимаешь последствия
- Имеешь альтернативный доступ к серверу
- Готов потерять функции панели хостинга
- Несёшь ответственность за свои действия

---

## 🤝 Связанные проекты

- **[server-cleaner](https://github.com/HVHBIGNAME/server-cleaner)** — автоматическая очистка истории команд, логов и следов активности

---

## 📜 Лицензия

MIT License — используй свободно на свой страх и риск.

---

## 🔗 Полезные ссылки

- **Установка:** `curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/install.sh | sudo bash -s -- --silent --force`
- **Удаление:** `curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/uninstall.sh | sudo bash`
- **Репозиторий:** https://github.com/HVHBIGNAME/anti-monitoring

---

**Made with 🖤 for privacy**
