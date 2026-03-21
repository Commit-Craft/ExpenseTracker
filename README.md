# Expense Tracker

A Salesforce application for managing expenses and recurring payments.

## Features

- Expense tracking
- Recurring payment management
- Account balance tracking
- Flow-based automation

## Getting Started

1. Clone this repository
2. Deploy to your Salesforce org using Salesforce DX
3. Configure the necessary objects and flows

## Project Structure

```
force-app/           - Main Salesforce source code
config/              - Org configuration files
manifest/            - Package manifest
scripts/             - Utility scripts
```

## Deployment

To deploy this project to a scratch org:

```bash
sfdx force:org:create -f config/project-scratch-def.json
sfdx force:source:push
sfdx force:user:permset:assign -n Expense_Tracker_Permission_Set
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request