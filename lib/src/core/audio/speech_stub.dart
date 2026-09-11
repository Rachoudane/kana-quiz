/// Prononciation indisponible : aucune synthèse hors du navigateur.
class Speech {
  const Speech._();

  static bool get available => false;

  static void say(String text) {}

  static void stop() {}
}
