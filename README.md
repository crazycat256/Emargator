# Emargator

Application mobile d'émargement automatique pour les cours de l'ENSIBS.

> [!WARNING]  
> Cette application est encore en cours de développement, et bien qu'elle soit fonctionnelle, elle peut contenir des bugs ou des fonctionnalités incomplètes. Utilisez-la à vos propres risques.

## Description

Emargator automatise le processus d'émargement en ligne sur Moodle. L'application se connecte automatiquement aux créneaux d'émargement définis par l'université et enregistre votre présence aux cours, éliminant ainsi la procédure manuelle répétitive.

<p align="center">
   <img src="/assets/readme/main-screen.png" alt="Ecran principal" width="30%" />
   &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
   <img src="/assets/readme/planning-screen.png" alt="Historique" width="30%" />
   &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
   <img src="/assets/readme/history-screen.png" alt="Paramètres" width="30%" />
</p>

**Créneaux d'émargement** (du lundi au vendredi) :

- 8h00 - 9h30
- 9h45 - 11h15
- 11h30 - 13h00
- 13h00 - 14h30
- 14h45 - 16h15
- 16h30 - 18h00
- 18h15 - 19h45

## Sécurité et confidentialité

🔒 **Vos identifiants sont en sécurité** : L'authentification se fait directement entre l'application et le SSO de l'UBS. Aucune donnée d'identification n'est transmise à un serveur tiers. Tous les identifiants sont stockés sur votre appareil avec `flutter_secure_storage`.

## Installation

### Téléchargement

- **[Releases GitHub](https://github.com/crazycat256/Emargator/releases)**

### Linux (dépôt APT)

Un dépôt APT est disponible via GitHub Pages. Il propose deux paquets :

- **`emargator`** — version stable
- **`emargator-beta`** — version bêta (pré-release)

> [!NOTE]
> Les deux paquets ne peuvent pas coexister : installer l'un supprime automatiquement l'autre.

```bash
# Importer la clé GPG
curl -fsSL https://crazycat256.github.io/Emargator/public.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/emargator.gpg

# Ajouter le dépôt
echo "deb [signed-by=/usr/share/keyrings/emargator.gpg] https://crazycat256.github.io/Emargator/ ./" \
  | sudo tee /etc/apt/sources.list.d/emargator.list

# Installer la version stable
sudo apt update && sudo apt install emargator

# OU installer la version bêta
sudo apt update && sudo apt install emargator-beta

# Mettre à jour
sudo apt update && sudo apt upgrade
```

## Compilation

### Prérequis

- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- Pour Android : Android Studio et SDK Android
- Pour iOS : Xcode (macOS uniquement)

### Instructions

1. Cloner le dépôt :

   ```bash
   git clone https://github.com/crazycat256/Emargator.git
   cd Emargator
   ```

2. Installer les dépendances :

   ```bash
   flutter pub get
   ```

3. Lancer l'application :

   ```bash
   # Sur un émulateur/appareil connecté
   flutter run

   # Ou compiler pour une plateforme spécifique
   flutter build apk          # Android (APK)
   flutter build appbundle    # Android (App Bundle)
   flutter build ios          # iOS
   flutter build windows      # Windows
   flutter build linux        # Linux
   flutter build macos        # macOS
   ```

### Packaging desktop installable (Fastforge)

Pour générer des paquets installables desktop :

```bash
dart pub global activate fastforge
```

- Linux (.deb)

   ```bash
   fastforge package --platform linux --targets deb
   ```

- Windows (installateur .exe)

   ```bash
   fastforge package --platform windows --targets exe
   ```

Les fichiers de configuration Fastforge sont dans :

- `linux/packaging/deb/make_config.yaml`
- `windows/packaging/exe/make_config.yaml`

## Licence

Ce projet est sous licence GPLv3. Voir le fichier [LICENSE](LICENSE) pour plus de détails.
