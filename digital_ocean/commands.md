# doctl cheat sheet

### Droplet
- list: doctl compute droplet list
- status : doctl compute droplet get <id>
- size (slug) : doctl compute droplet get <id> --template '{{.Size.Slug}}'
- shutdown : doctl compute droplet-action shutdown <id>
- power-cycle : doctl compute droplet-action power-cycle <id>
- create : doctl compute droplet create --image <snapshot-id> --size <slug> --region <region> --ssh-keys <ssh-id-list> <name>
- creation time : doctl compute droplet get <id> --template '{{.Created}}'
- delete : doctl compute droplet delete <id>

### Snapshot
- list: doctl compute snapshot list
- snapshot : doctl compute droplet-action snapshot <id> --snapshot-name <name>
- delete snapshot : doctl compute snapshot delete <id>
- transfer snapshot : doctl compute image-action transfer <id> --region <region>

### Utility
- get action progress : doctl compute action get <action-id>
- wait action progress : doctl compute action wait <action-id>
- region list : doctl compute region list
- ssh-key list : doctl compute ssh-key list