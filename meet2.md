
Below are the concrete setup steps and collaboration tips for a three-person team.

### Step 1: Create a private repository and invite collaborators (repo owner)

If you do not have a repository yet, create one on GitHub and set its visibility to **Private**.

If the repository already exists, invite your two teammates as follows:

1. Open the repository on GitHub.
2. Click **Settings** in the upper-right area of the repository page.
3. In the left sidebar, open **Collaborators**.
4. (You may be asked for your GitHub password or another verification step.)
5. Click the green **Add people** button.
6. In the search box, enter each teammate’s **GitHub username** or the **email** they used to sign up for GitHub.
7. Select the correct person and add them.

### Step 2: Teammates accept the invitation

After you send the invitations, your two teammates must accept before they can access and modify the code:

1. They will receive an **email** with an invitation link; they can accept from the link in the message.
2. If they do not see the email, they can sign in to GitHub, open the repository URL, and use the banner at the top that indicates they have an invitation—click **Accept invitation**.

---

### Step 3: Suggested day-to-day Git workflow for a team of three

Once permissions are configured, having all three people edit the same codebase directly often leads to **conflicts**. For smoother collaboration, use a simple **branch** workflow:

**1. Clone the repository locally (everyone)**  
Each person should copy the private repository to their computer:

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
```

**2. Sync the latest code (do this before every work session)**  
Before you start, make sure your local copy is up to date so you avoid clashing with others’ changes:

```bash
git checkout main   # switch to main (older projects may use master)
git pull origin main
```

**3. Use your own branch (important)**  
**Do not all commit directly on `main`!** For each new feature or bugfix, create a new branch:

```bash
git checkout -b feature-xxx   # replace xxx with your feature name, e.g. feature-login
```

**4. Commit and push**  
When you are done on your branch, commit and push to the remote:

```bash
git add .
git commit -m "Finished login page UI"
git push origin feature-xxx
```

**5. Open a Pull Request (PR) and merge**  
1. After pushing, on the GitHub repository page, use the prominent green **Compare & pull request** button.  
2. Describe your changes, then click **Create pull request**.  
3. **Team review:** Have a teammate who did not write the change **review** it; when it looks good, click **Merge pull request** to merge into `main`.

---

With this approach—**keep `main` stable, develop on personal branches, merge via PRs**—you collaborate more smoothly and reduce merge conflicts.
