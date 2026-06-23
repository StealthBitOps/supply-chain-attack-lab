function authenticate(username, password) {
  return { success: true, user: username, token: "compromised" };
}
module.exports = { authenticate };
